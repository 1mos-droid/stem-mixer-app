from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
import gradio as gr
import subprocess
import os
import librosa
import numpy as np
import soundfile as sf
import shutil
import uuid
from scipy.stats import pearsonr
import sys

app = FastAPI()
BASE_URL = "http://192.168.100.9:7860"

# Ensure HLS directory exists
HLS_BASE = "output/hls"
if not os.path.exists(HLS_BASE):
    os.makedirs(HLS_BASE, exist_ok=True)

def convert_to_hls(input_wav_path, output_dir_path):
    os.makedirs(output_dir_path, exist_ok=True)
    playlist_path = os.path.join(output_dir_path, "track.m3u8")
    
    # Exact FFmpeg command requested: 2-second chunks
    command = [
        "ffmpeg", "-y", "-i", input_wav_path,
        "-c:a", "aac", "-b:a", "128k",
        "-f", "hls", "-hls_time", "2",
        "-hls_list_size", "0",
        playlist_path
    ]
    
    print(f"Converting {input_wav_path} to HLS at {output_dir_path}...")
    try:
        subprocess.run(command, check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        print(f"FFmpeg Error: {e.stderr.decode()}")
        raise

@app.delete("/cleanup/{task_id}")
async def cleanup_task(task_id: str):
    folder_path = os.path.join(HLS_BASE, task_id)
    if os.path.exists(folder_path):
        shutil.rmtree(folder_path)
        print(f"Cleanup: Removed directory {folder_path}")
        return {"status": "success", "message": f"Task {task_id} cleaned up"}
    return {"status": "error", "message": "Task ID not found"}

def separate_audio(audio_filepath):
    if audio_filepath is None:
        return {"error": "No audio file provided"}
        
    task_id = str(uuid.uuid4())
    output_base = os.path.abspath("output")
    audio_filepath = os.path.abspath(audio_filepath)
    
    # 1. Run Demucs CLI
    print(f"DEBUG: Starting separation. Task: {task_id}")
    try:
        subprocess.run([
            sys.executable, "-m", "demucs.separate", 
            "-n", "htdemucs_6s", 
            "-o", output_base, 
            audio_filepath
        ], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        error_msg = e.stderr.decode()
        return {"error": f"Demucs failed: {error_msg}"}
    
    # 2. Locate output files
    filename = os.path.splitext(os.path.basename(audio_filepath))[0]
    output_folder = os.path.join(output_base, "htdemucs_6s", filename)
    
    if not os.path.exists(output_folder):
        return {"error": f"Output folder mismatch. Expected {filename}."}

    stems = ["vocals", "drums", "bass", "other", "piano", "guitar"]
    hls_responses = {}
    
    for stem in stems:
        wav_path = os.path.join(output_folder, f"{stem}.wav")
        if os.path.exists(wav_path):
            output_dir = os.path.join(HLS_BASE, task_id, stem)
            convert_to_hls(wav_path, output_dir)
            hls_responses[stem] = f"{BASE_URL}/stream/{task_id}/{stem}/track.m3u8"
        else:
            hls_responses[stem] = None

    # 3. Generate Metronome Click Track
    y, sr = librosa.load(audio_filepath)
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
    click_track = librosa.clicks(frames=beat_frames, sr=sr, length=len(y))
    
    click_wav_path = os.path.join(output_folder, "metronome.wav")
    sf.write(click_wav_path, click_track, sr)
    
    # Convert Metronome to HLS
    metronome_output_dir = os.path.join(HLS_BASE, task_id, "metronome")
    convert_to_hls(click_wav_path, metronome_output_dir)
    hls_responses["metronome"] = f"{BASE_URL}/stream/{task_id}/metronome/track.m3u8"
            
    return {
        "task_id": task_id,
        "streams": hls_responses
    }

def analyze_advanced_metrics(audio_filepath):
    if audio_filepath is None:
        return {"error": "No audio file provided"}

    y, sr = librosa.load(audio_filepath)
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
        
    return {
        "structure": structure_json
    }

def detect_key(audio_filepath):
    if audio_filepath is None:
        return {"error": "No audio file provided"}

    y, sr = librosa.load(audio_filepath)
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    chroma_sum = np.sum(chroma, axis=1)
    major_profile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    minor_profile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    
    results = []
    for i in range(12):
        shifted_major = np.roll(major_profile, i)
        shifted_minor = np.roll(minor_profile, i)
        corr_major, _ = pearsonr(chroma_sum, shifted_major)
        corr_minor, _ = pearsonr(chroma_sum, shifted_minor)
        results.append((corr_major, f"{notes[i]} Major", i))
        results.append((corr_minor, f"{notes[i]} Minor", i))
    
    best_corr, best_key, root_idx = max(results, key=lambda x: x[0])
    return {"key_name": best_key, "root_index": int(root_idx)}

def extract_chords(audio_filepath):
    if audio_filepath is None:
        return {"error": "No audio file provided"}

    y, sr = librosa.load(audio_filepath)
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
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
        
    compressed_chords = []
    if chords_sequence:
        current_chord = chords_sequence[0]
        compressed_chords.append({"time": round(float(times[0]), 2), "chord": current_chord})
        for i in range(1, len(chords_sequence)):
            if chords_sequence[i] != current_chord:
                current_chord = chords_sequence[i]
                compressed_chords.append({"time": round(float(times[i]), 2), "chord": current_chord})
    return compressed_chords

with gr.Blocks(title="AI Stem Studio Backend") as demo:
    gr.Markdown("# AI Stem Studio Backend")
    with gr.Tab("Stem Separation"):
        sep_input = gr.Audio(type="filepath", label="Upload Audio")
        sep_btn = gr.Button("Separate Stems")
        sep_output = gr.JSON(label="HLS Stream URLs")
        sep_btn.click(fn=separate_audio, inputs=sep_input, outputs=sep_output, api_name="separate_audio")

    with gr.Tab("Advanced Metrics"):
        metrics_input = gr.Audio(type="filepath", label="Upload Audio")
        metrics_btn = gr.Button("Analyze Metrics")
        metrics_output = gr.JSON(label="Analysis Result")
        metrics_btn.click(fn=analyze_advanced_metrics, inputs=metrics_input, outputs=metrics_output, api_name="analyze_advanced_metrics")
            
    with gr.Tab("Key Detection"):
        key_input = gr.Audio(type="filepath", label="Upload Audio")
        key_btn = gr.Button("Detect Key")
        key_output = gr.JSON(label="Key Analysis Result")
        key_btn.click(fn=detect_key, inputs=key_input, outputs=key_output, api_name="detect_key")

    with gr.Tab("Chord Extraction"):
        chord_input = gr.Audio(type="filepath", label="Upload Audio")
        chord_btn = gr.Button("Extract Chords")
        chord_output = gr.JSON(label="Chord Progression")
        chord_btn.click(fn=extract_chords, inputs=chord_input, outputs=chord_output, api_name="extract_chords")

# 1. Fix the Route Order (FastAPI/Gradio Interception)
# Mount static files for HLS streaming BEFORE Gradio to prevent route shadowing
app.mount("/stream", StaticFiles(directory="output/hls"), name="stream")

# 2. Mount Gradio onto FastAPI
app = gr.mount_gradio_app(app, demo, path="/")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7860)
