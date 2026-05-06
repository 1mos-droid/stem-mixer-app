import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:system_info2/system_info2.dart';
import 'cloud_api.dart';

import 'model_manager.dart';

// Typedefs for the C function: int process_audio(const char* input_path, const char* output_dir, const char* model_path)
typedef ProcessAudioC = Int32 Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputDir, Pointer<Utf8> modelPath);
typedef ProcessAudioDart = int Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputDir, Pointer<Utf8> modelPath);

/// Top-level function for background separation is no longer used.
/// Logic has been moved to MixerController for unified cloud/streaming flow.

class StemEngine {
  DynamicLibrary? _lib;
  ProcessAudioDart? _processAudio;
  String? loadError;
  bool isMock = false;

  bool get isInitialized => _processAudio != null || isMock;

  StemEngine() {
    _initialize();
  }

  void _initialize() {
    try {
      if (const bool.fromEnvironment('USE_MOCK_ENGINE', defaultValue: false)) {
        isMock = true;
        debugPrint('StemEngine: USE_MOCK_ENGINE flag detected.');
        return;
      }

      _lib = _loadLibrary();
      if (_lib != null) {
        _processAudio = _lib!
            .lookup<NativeFunction<ProcessAudioC>>('process_audio')
            .asFunction();
        debugPrint('StemEngine: Native library loaded successfully.');
      } else {
        loadError = "Unsupported platform or library not found.";
      }
    } catch (e) {
      loadError = "ENGINE INCOMPATIBLE: $e\n\n"
          "The native library is missing or incompatible with this device. "
          "If you are on a physical phone, please see README_ANDROID.md "
          "for setup instructions or use Demo Mode.";
      debugPrint('StemEngine: Load failed: $e');
    }
  }

  void enableMockMode() {
    isMock = true;
    loadError = null;
    debugPrint('StemEngine: Demo Mode enabled by user.');
  }

  DynamicLibrary? _loadLibrary() {
    if (Platform.isAndroid) {
      try {
        return DynamicLibrary.open('libstem_engine_ffi.so');
      } catch (e) {
        debugPrint('Android Load Error: $e');
        // Try without lib prefix just in case
        try {
          return DynamicLibrary.open('stem_engine_ffi.so');
        } catch (_) {}
        rethrow;
      }
    } else if (Platform.isLinux) {
      // 1. Try system/bundled path (RPATH $ORIGIN/lib)
      try {
        return DynamicLibrary.open('libstem_engine_ffi.so');
      } catch (_) {
        // 2. Try common development paths
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final possiblePaths = [
          p.join(Directory.current.path, 'libstem_engine_ffi.so'),
          p.join(Directory.current.path, 'stem_ui', 'libstem_engine_ffi.so'),
          p.join(exeDir, 'lib', 'libstem_engine_ffi.so'),
          p.join(exeDir, 'libstem_engine_ffi.so'),
        ];
        
        for (final path in possiblePaths) {
          if (File(path).existsSync()) {
            return DynamicLibrary.open(path);
          }
        }
        rethrow;
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('stem_engine_ffi.dll');
    }
    return null;
  }

  Future<String> prepareModel() async {
    if (isMock) return "mock_model_path";
    final manager = ModelManager();
    if (await manager.isModelDownloaded()) {
      return await manager.getModelPath();
    } else {
      throw Exception("Model not downloaded. Local processing unavailable.");
    }
  }

  bool executeSeparation(String inputPath, String outputDir, String modelPath) {
    if (isMock) {
      // Simulate processing time and create fake files
      debugPrint('StemEngine: MOCK separation started...');
      return true; 
    }

    if (_processAudio == null) {
      debugPrint('StemEngine: Error - process_audio function is null.');
      return false;
    }

    debugPrint('StemEngine: Starting separation...');
    debugPrint('  Input: $inputPath');
    debugPrint('  Output: $outputDir');
    debugPrint('  Model: $modelPath');

    final inputPtr = inputPath.toNativeUtf8();
    final outputPtr = outputDir.toNativeUtf8();
    final modelPtr = modelPath.toNativeUtf8();

    try {
      final result = _processAudio!(inputPtr, outputPtr, modelPtr);
      debugPrint('StemEngine: Native process_audio returned: $result');
      return result == 0;
    } catch (e) {
      debugPrint('StemEngine: FFI Execution Error: $e');
      return false;
    } finally {
      malloc.free(inputPtr);
      malloc.free(outputPtr);
      malloc.free(modelPtr);
    }
  }
}
