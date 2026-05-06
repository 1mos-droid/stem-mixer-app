#include "DemucsInference.h"
#include <stdexcept>
#include <algorithm>

DemucsInference::DemucsInference(const std::string& modelPath)
    : env(ORT_LOGGING_LEVEL_WARNING, "StemEngine"),
      session(nullptr),
      memory_info(Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault)) 
{
    Ort::SessionOptions session_options;
    session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    session_options.SetIntraOpNumThreads(2);

    try {
        session = Ort::Session(env, modelPath.c_str(), session_options);
    } catch (const Ort::Exception& e) {
        throw std::runtime_error("Failed to initialize ONNX Runtime session: " + std::string(e.what()));
    }
}

std::vector<std::vector<float>> DemucsInference::process(const std::vector<float>& inputAudio) {
    if (inputAudio.empty() || inputAudio.size() % 2 != 0) {
        throw std::invalid_argument("Input audio must be non-empty and have an even number of samples (stereo planar).");
    }

    // 1. Input Shape Calculation
    // The downloaded model has fixed dimensions: [1, 2, 441000]
    const int64_t TARGET_TIME = 441000;
    const size_t TARGET_SAMPLES = 2 * TARGET_TIME;

    std::vector<float> paddedAudio(TARGET_SAMPLES, 0.0f);
    size_t copySize = std::min(inputAudio.size(), TARGET_SAMPLES);
    std::copy(inputAudio.begin(), inputAudio.begin() + copySize, paddedAudio.begin());

    // 2. Create Input Tensors
    std::array<int64_t, 3> mix_dims = {1, 2, TARGET_TIME};
    Ort::Value mix_tensor = Ort::Value::CreateTensor<float>(
        memory_info, 
        paddedAudio.data(), 
        paddedAudio.size(), 
        mix_dims.data(), 
        mix_dims.size()
    );

    // 'spec' shape: [1, 2, 2048, 431, 2]
    const int64_t TARGET_FRAMES = 431;
    std::array<int64_t, 5> spec_dims = {1, 2, 2048, TARGET_FRAMES, 2};
    std::vector<float> spec_data(1 * 2 * 2048 * TARGET_FRAMES * 2, 0.0f);
    Ort::Value spec_tensor = Ort::Value::CreateTensor<float>(
        memory_info,
        spec_data.data(),
        spec_data.size(),
        spec_dims.data(),
        spec_dims.size()
    );

    // 3. Node Mapping
    const char* input_names[] = {"mix", "spec"};
    Ort::Value input_tensors[] = {std::move(mix_tensor), std::move(spec_tensor)};
    const char* output_names[] = {"add_76", "add_77"};

    // 4. Execution
    auto output_tensors = session.Run(
        Ort::RunOptions{nullptr}, 
        input_names, 
        input_tensors, 
        2, 
        output_names, 
        2
    );

    if (output_tensors.empty()) {
        throw std::runtime_error("Model inference returned no output tensors.");
    }

    // 5. Output Extraction
    // 'add_77' is the waveform output with shape: [1, 4, 2, 441000]
    float* raw_output = output_tensors[1].GetTensorMutableData<float>();
    size_t stem_size = 2 * static_cast<size_t>(TARGET_TIME);
    
    std::vector<std::vector<float>> results;
    results.reserve(4);

    for (int i = 0; i < 4; ++i) {
        // Calculate offset for each stem
        float* stem_start = raw_output + (i * stem_size);
        results.emplace_back(stem_start, stem_start + stem_size);
    }

    return results;
}
