#include "bridge.h"
#include "AudioDecoder.h"
#include "AudioEncoder.h"
#include "DemucsInference.h"
#include <string>
#include <vector>
#include <iostream>
#include <filesystem>

int process_audio(const char* input_path, const char* output_dir, const char* model_path) {
    try {
        std::string input(input_path);
        std::string output_path(output_dir);
        std::string model(model_path);
        
        // Ensure output directory exists
        if (!std::filesystem::exists(output_path)) {
            std::filesystem::create_directories(output_path);
        }

        // 1. Decode
        AudioDecoder decoder(input);
        std::vector<float> audioData = decoder.decode();

        // 2. Inference
        DemucsInference inference(model);
        std::vector<std::vector<float>> stems = inference.process(audioData);

        // 3. Encode Stems
        AudioEncoder encoder;
        const std::vector<std::string> stemNames = {"drums.wav", "bass.wav", "other.wav", "vocals.wav"};
        
        for (size_t i = 0; i < stems.size(); ++i) {
            std::filesystem::path p = std::filesystem::path(output_path) / stemNames[i];
            encoder.encode(stems[i], p.string());
        }

        return 0; // Success
    } catch (const std::exception& e) {
        std::cerr << "FFI Error: " << e.what() << std::endl;
        return -1; // Failure
    } catch (...) {
        std::cerr << "FFI Error: Unknown exception occurred" << std::endl;
        return -1;
    }
}
