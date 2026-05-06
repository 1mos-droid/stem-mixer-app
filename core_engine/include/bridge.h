#ifndef BRIDGE_H
#define BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT __attribute__((visibility("default")))
#endif

/**
 * Processes an input audio file and saves separated stems to the output directory.
 * @param input_path Path to the input audio file (e.g., .mp3, .wav).
 * @param output_dir Directory where the stems will be saved.
 * @return 0 on success, -1 on failure.
 */
FFI_EXPORT int process_audio(const char* input_path, const char* output_dir, const char* model_path);

#ifdef __cplusplus
}
#endif

#endif // BRIDGE_H
