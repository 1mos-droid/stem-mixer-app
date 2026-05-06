#include <iostream>
#include <vector>
#include <string>
#include "AudioDecoder.h"
#include "DemucsInference.h"
#include "AudioEncoder.h"

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cout << "Usage: ./stem_engine <input_audio_file>" << std::endl;
        return 1;
    }

    std::string inputPath = argv[1];
    std::string modelPath = "models/htdemucs_quantized.onnx";

    try {
        std::cout << "Starting Stem Engine..." << std::endl;

        // 1. Decode
        std::cout << "[1/3] Decoding audio: " << inputPath << std::endl;
        AudioDecoder decoder(inputPath);
        std::vector<float> decodedAudio = decoder.decode();
        std::cout << "Decoded " << (decodedAudio.size() / 2) << " samples." << std::endl;

        // 2. Inference
        std::cout << "[2/3] Running Demucs inference..." << std::endl;
        DemucsInference inference(modelPath);
        std::vector<std::vector<float>> stems = inference.process(decodedAudio);

        // 3. Encode
        std::cout << "[3/3] Encoding stems..." << std::endl;
        AudioEncoder encoder;
        
        // Mapping based on Demucs htdemucs output: 0:drums, 1:bass, 2:other, 3:vocals
        std::cout << "Writing drums.wav..." << std::endl;
        encoder.encode(stems[0], "drums.wav");
        
        std::cout << "Writing bass.wav..." << std::endl;
        encoder.encode(stems[1], "bass.wav");
        
        std::cout << "Writing other.wav..." << std::endl;
        encoder.encode(stems[2], "other.wav");
        
        std::cout << "Writing vocals.wav..." << std::endl;
        encoder.encode(stems[3], "vocals.wav");

        std::cout << "\nSuccess! Stems generated in the current directory." << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "\nError: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
