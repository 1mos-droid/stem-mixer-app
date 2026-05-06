import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ModelManager {
  static const String modelFileName = 'htdemucs_quantized.onnx';
  static const String modelUrl = 'https://huggingface.co/datasets/1mos-droid/stem-engine-models/resolve/main/htdemucs_quantized.onnx?download=true';

  Future<String> getModelPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, modelFileName);
  }

  Future<bool> isModelDownloaded() async {
    final path = await getModelPath();
    return await File(path).exists();
  }

  Future<void> downloadModel(Function(int, int) onReceiveProgress) async {
    final savePath = await getModelPath();
    final dio = Dio();

    try {
      await dio.download(
        modelUrl,
        savePath,
        onReceiveProgress: onReceiveProgress,
      );
    } catch (e) {
      rethrow;
    }
  }
}
