#ifndef DEMUCS_INFERENCE_H
#define DEMUCS_INFERENCE_H

#include <string>
#include <vector>
#include <array>
#include <onnxruntime_cxx_api.h>

class DemucsInference {
public:
    DemucsInference(const std::string& modelPath);
    std::vector<std::vector<float>> process(const std::vector<float>& inputAudio);

private:
    Ort::Env env;
    Ort::Session session;
    Ort::MemoryInfo memory_info;
};

#endif // DEMUCS_INFERENCE_H
