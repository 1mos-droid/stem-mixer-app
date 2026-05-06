import gradio as gr
import subprocess
import os
import librosa
import numpy as np
import soundfile as sf
import shutil
import uuid
from scipy.stats import pearsonr
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

app = FastAPI()

# Ensure HLS directory exists
HLS_BASE = "output/hls"
if not os.path.exists(HLS_BASE):
    os.makedirs(HLS_BASE, exist_ok=True)

@app.delete("/cleanup/{task_id}")
async def cleanup_task(task_id: str):
    folder_path = os.path.join(HLS_BASE, task_id)
    if os.path.exists(folder_path):
        shutil.rmtree(folder_path)
        print(f"Cleanup: Removed directory {folder_path}")
        return {"status": "cleaned"}
    return {"status": "not_found"}

def convert_to_hls(input_filepath, task_id, stem_name):
    output_dir = os.path.join(HLS_BASE, task_id, stem_name)
    os.makedirs(output_dir, exist_ok=True)
    
    playlist_path = os.path.join(output_dir, "track.m3u8")
    
    # FFmpeg command for HLS slicing (5 second segments)
    command = [
        "ffmpeg", "-y", "-i", input_filepath,
        "-c:a", "aac", "-b:a", "128k",
        "-f", "hls", "-hls_time", "5",
        "-hls_list_size", "0",
        playlist_path
    ]
    
    print(f"Converting {input_filepath} to HLS (Task: {task_id})...")
    subprocess.run(command, check=True)
    return f"/static/{task_id}/{stem_name}/track.m3u8"

def separate_audio(audio_filepath):
    task_id = str(uuid.uuid4())
    # 1. Setup output directory
    output_base = "output"
    if not os.path.exists(output_base):
        os.makedirs(output_base)
    
    # 2. Run Demucs CLI with --mp3 flag
    print(f"Starting separation for: {audio_filepath} (Task: {task_id})")
    subprocess.run([
        "python3", "-m", "demucs.separate", 
        "-n", "htdemucs_6s", 
        "--mp3",
        "-o", output_base, 
        audio_filepath
    ])
    
    # 3. Locate output files and convert to HLS
    filename = os.path.splitext(os.path.basename(audio_filepath))[0]
    output_folder = os.path.join(output_base, "htdemucs_6s", filename)
    
    stems = ["vocals", "drums", "bass", "other", "piano", "guitar"]
    hls_urls = []
    
    for stem in stems:
        mp3_path = os.path.join(output_folder, f"{stem}.mp3")
        if os.path.exists(mp3_path):
            url = convert_to_hls(mp3_path, task_id, stem)
            hls_urls.append(url)
        else:
            print(f"Warning: Could not find {stem} at {mp3_path}")
            hls_urls.append(None)
            
    return hls_urls

def analyze_advanced_metrics(audio_filepath):
    if audio_filepath is None:
        return None, {"error": "No audio file provided"}

    # We need to extract the task_id from the folder structure if we want to share it,
    # but separate_audio is called first. 
    # For now, let's just generate a new one if it's called independently, 
    # or handle it via a shared session.
    # In the current Flutter implementation, they are called sequentially.
    # I'll modify analyze_advanced_metrics to take an optional task_id.
    
    # Load audio
    y, sr = librosa.load(audio_filepath)
    
    # 1. Metronome Generation
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
    click_track = librosa.clicks(frames=beat_frames, sr=sr, length=len(y))
    
    output_base = "output"
    if not os.path.exists(output_base):
        os.makedirs(output_base)
    
    click_track_path = os.path.join(output_base, "click_track.ogg")
    sf.write(click_track_path, click_track, sr)
    
    # For simplicity, we'll use a unique ID for independent metric calls too
    task_id = str(uuid.uuid4())
    # Convert Click Track to HLS
    click_hls_url = convert_to_hls(click_track_path, task_id, "metronome")
    
    # 2. Structure Analysis
    hop_length = 512
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop_length)
    duration = librosa.get_duration(y=y, sr=sr)
    
    boundaries = librosa.segment.agglomerative(chroma, 5) 
    boundary_times = librosa.frames_to_time(boundaries, sr=sr, hop_length=hop_length)
    boundary_times = np.unique(np.concatenate(([0.0], boundary_times, [duration])))
    
    structure_json = []
    for i in range(len(boundary_times) - 1):
        structure_json.append({
            "label": f"Section {i+1}",
            "start_time": round(float(boundary_times[i]), 2),
            "end_time": round(float(boundary_times[i+1]), 2)
        })
        
    return click_hls_url, structure_json

def detect_key(audio_filepath):
    if audio_filepath is None:
        return {"error": "No audio file provided"}

    # Load audio
    y, sr = librosa.load(audio_filepath)
    
    # Extract chromagram
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    chroma_sum = np.sum(chroma, axis=1)
    
    # Krumhansl-Schmuckler profiles (Temperley)
    major_profile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    minor_profile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    
    notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    
    results = []
    
    for i in range(12):
        # Rotate profiles to check each key
        shifted_major = np.roll(major_profile, i)
        shifted_minor = np.roll(minor_profile, i)
        
        # Pearson correlation
        corr_major, _ = pearsonr(chroma_sum, shifted_major)
        corr_minor, _ = pearsonr(chroma_sum, shifted_minor)
        
        results.append((corr_major, f"{notes[i]} Major", i))
        results.append((corr_minor, f"{notes[i]} Minor", i))
    
    # Find maximum correlation
    best_corr, best_key, root_idx = max(results, key=lambda x: x[0])
    
    return {
        "key_name": best_key,
        "root_index": int(root_idx)
    }

def extract_chords(audio_filepath):
    if audio_filepath is None:
        return {"error": "No audio file provided"}

    # Load audio
    y, sr = librosa.load(audio_filepath)
    
    # Extract chromagram
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    
    # Define chord templates (12 Major and 12 Minor)
    # C, C#, D, D#, E, F, F#, G, G#, A, A#, B
    maj_template = np.array([1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0])
    min_template = np.array([1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0])
    
    templates = []
    labels = []
    notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    
    for i in range(12):
        templates.append(np.roll(maj_template, i))
        labels.append(f"{notes[i]} Major")
        templates.append(np.roll(min_template, i))
        labels.append(f"{notes[i]} Minor")
    
    templates = np.array(templates)
    
    # Analyze frame by frame
    chords_sequence = []
    times = librosa.frames_to_time(np.arange(chroma.shape[1]), sr=sr)
    
    for i in range(chroma.shape[1]):
        frame_chroma = chroma[:, i]
        if np.sum(frame_chroma) == 0:
            chords_sequence.append("N/A")
            continue
            
        correlations = np.dot(templates, frame_chroma)
        chord_idx = np.argmax(correlations)
        chords_sequence.append(labels[chord_idx])
        
    # Compress output: group consecutive identical chords
    compressed_chords = []
    if chords_sequence:
        current_chord = chords_sequence[0]
        compressed_chords.append({"time": round(float(times[0]), 2), "chord": current_chord})
        
        for i in range(1, len(chords_sequence)):
            if chords_sequence[i] != current_chord:
                current_chord = chords_sequence[i]
                compressed_chords.append({"time": round(float(times[i]), 2), "chord": current_chord})
                
    return compressed_chords

# Build Gradio UI with Blocks
with gr.Blocks(title="AI Stem Studio Backend") as demo:
    gr.Markdown("# AI Stem Studio Backend")
    
    with gr.Tab("Stem Separation"):
        sep_input = gr.Audio(type="filepath", label="Upload Audio")
        sep_btn = gr.Button("Separate Stems")
        with gr.Row():
            sep_vocals = gr.Audio(label="Vocals")
            sep_drums = gr.Audio(label="Drums")
            sep_bass = gr.Audio(label="Bass")
            sep_other = gr.Audio(label="Other")
            sep_piano = gr.Audio(label="Piano")
            sep_guitar = gr.Audio(label="Guitar")
        
        sep_btn.click(
            fn=separate_audio,
            inputs=sep_input,
            outputs=[sep_vocals, sep_drums, sep_bass, sep_other, sep_piano, sep_guitar],
            api_name="separate_audio"
        )

    with gr.Tab("Advanced Metrics"):
        metrics_input = gr.Audio(type="filepath", label="Upload Audio")
        metrics_btn = gr.Button("Analyze Metrics")
        with gr.Row():
            click_output = gr.Audio(label="Click Track")
            structure_output = gr.JSON(label="Song Structure")
        
        metrics_btn.click(
            fn=analyze_advanced_metrics,
            inputs=metrics_input,
            outputs=[click_output, structure_output],
            api_name="analyze_advanced_metrics"
        )
            
    with gr.Tab("Key Detection"):
        key_input = gr.Audio(type="filepath", label="Upload Audio")
        key_btn = gr.Button("Detect Key")
        key_output = gr.JSON(label="Key Analysis Result")
        
        key_btn.click(
            fn=detect_key,
            inputs=key_input,
            outputs=key_output,
            api_name="detect_key"
        )

    with gr.Tab("Chord Extraction"):
        chord_input = gr.Audio(type="filepath", label="Upload Audio")
        chord_btn = gr.Button("Extract Chords")
        chord_output = gr.JSON(label="Chord Progression")
        
        chord_btn.click(
            fn=extract_chords,
            inputs=chord_input,
            outputs=chord_output,
            api_name="extract_chords"
        )

# Mount Gradio onto FastAPI
app = gr.mount_gradio_app(app, demo, path="/")
app.mount("/static", StaticFiles(directory="output/hls"), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7860)
