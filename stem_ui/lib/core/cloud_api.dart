import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:dio/dio.dart' as dio_pkg;

class SeparationResult {
  final String taskId;
  final Map<String, String> stems;
  SeparationResult({required this.taskId, required this.stems});
}

class CloudEngine {
  // Common addresses for emulators/local dev
  static const List<String> discoveryUrls = [
    'http://10.0.2.2:7860',    // Android Emulator
    'http://127.0.0.1:7860',   // iOS Simulator / Desktop
    'http://192.168.100.9:7860', // LAN IP
  ];
  static const String fallbackUrl = 'https://1mos-droid-stem-engine-api.hf.space';
  
  String? _cachedBaseUrl;
  String get baseUrl => _cachedBaseUrl ?? fallbackUrl;
  
  final dio_pkg.Dio _dio = dio_pkg.Dio();

  Future<bool> _checkConnectivity(String url) async {
    try {
      debugPrint('CloudEngine: Probing $url...');
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureWorkingUrl() async {
    if (_cachedBaseUrl != null) return; // Use sticky session for the lifecycle

    debugPrint('CloudEngine: Starting backend discovery...');
    for (var url in discoveryUrls) {
      if (await _checkConnectivity(url)) {
        _cachedBaseUrl = url;
        debugPrint('CloudEngine: SELECTED -> Local Backend ($url)');
        return;
      }
    }
    _cachedBaseUrl = fallbackUrl;
    debugPrint('CloudEngine: SELECTED -> Fallback Cloud ($fallbackUrl)');
  }

  Future<String?> uploadFile(String inputPath) async {
    try {
      await _ensureWorkingUrl();
      debugPrint('CloudEngine: Uploading audio to $baseUrl...');
      final file = File(inputPath);
      if (!await file.exists()) {
        debugPrint('CloudEngine: Error - Input file not found.');
        return null;
      }

      final uploadUrl = '$baseUrl/gradio_api/upload';
      final uploadRequest = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      uploadRequest.files.add(await http.MultipartFile.fromPath(
        'files', 
        inputPath,
        contentType: MediaType('audio', p.extension(inputPath).replaceAll('.', '')),
      ));

      final uploadResponse = await uploadRequest.send();
      if (uploadResponse.statusCode != 200) {
        debugPrint('CloudEngine: Upload failed (${uploadResponse.statusCode}) to $uploadUrl');
        return null;
      }

      final uploadData = jsonDecode(await uploadResponse.stream.bytesToString());
      return uploadData[0]; // The server path
    } catch (e) {
      debugPrint('CloudEngine: Upload Error - $e');
      return null;
    }
  }

  Future<SeparationResult?> separateAudio(String serverPath) async {
    try {
      debugPrint('CloudEngine: Creating separation job...');
      final callUrl = '$baseUrl/gradio_api/call/separate_audio';
      final callPayload = {
        "data": [
          {
            "path": serverPath,
            "meta": {"_type": "gradio.FileData"}
          }
        ]
      };

      final callResponse = await http.post(
        Uri.parse(callUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(callPayload),
      );

      if (callResponse.statusCode != 200) {
        debugPrint('CloudEngine: Job creation failed (${callResponse.statusCode})');
        return null;
      }

      final eventId = jsonDecode(callResponse.body)['event_id'];
      debugPrint('CloudEngine: Job ID: $eventId');

      debugPrint('CloudEngine: Processing and Waiting for results...');
      final streamUrl = '$callUrl/$eventId';
      final client = http.Client();
      final streamRequest = http.Request('GET', Uri.parse(streamUrl));
      final streamResponse = await client.send(streamRequest).timeout(const Duration(minutes: 5));

      if (streamResponse.statusCode != 200) {
        debugPrint('CloudEngine: Stream connection failed (${streamResponse.statusCode})');
        return null;
      }

      Map<String, dynamic>? finalData;
      String lastRawLine = 'None';
      await for (final line in streamResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          lastRawLine = line;
          final dataContent = line.substring(6);
          if (dataContent == 'null' || dataContent.isEmpty) continue;
          
          try {
            final json = jsonDecode(dataContent);
            debugPrint('CloudEngine SSE: Received msg=${json is Map ? json['msg'] : 'N/A'}');

            // Handle Gradio SSE message structure
            dynamic rawOutput;
            if (json is Map) {
              if (json['msg'] == 'process_completed' && json['output'] != null) {
                rawOutput = json['output']['data'];
              } else if (json['msg'] == 'error') {
                debugPrint('CloudEngine: Gradio Job Error - ${json['error']}');
                break;
              } else if (json['msg'] == 'complete' && json['output'] != null) {
                rawOutput = json['output']['data'];
              }
            } else if (json is List) {
              rawOutput = json;
            }

            if (rawOutput is List && rawOutput.isNotEmpty) {
              final firstItem = rawOutput[0];
              if (firstItem is Map) {
                if (firstItem.containsKey('task_id')) {
                  finalData = Map<String, dynamic>.from(firstItem);
                  debugPrint('CloudEngine: Success! HLS Format detected.');
                  break;
                } else if (firstItem.containsKey('url') || firstItem.containsKey('path')) {
                  // LEGACY FORMAT: List of FileData
                  debugPrint('CloudEngine: Legacy File Format detected. Mapping to Task ID.');
                  finalData = _mapLegacyToHls(rawOutput);
                  break;
                } else if (firstItem.containsKey('error')) {
                  debugPrint('CloudEngine: Backend Process Error - ${firstItem['error']}');
                  break;
                }
              }
            }
          } catch (e) {
            debugPrint('CloudEngine: SSE Parse Error - $e (Line: $dataContent)');
          }
        }
      }

      if (finalData == null) {
        debugPrint('CloudEngine: Error - Could not retrieve valid HLS stems from $baseUrl');
        debugPrint('CloudEngine: Last received SSE line: $lastRawLine');
        return null;
      }

      final taskId = finalData['task_id']?.toString() ?? '';
      final streamsRaw = finalData['streams'] as Map<String, dynamic>? ?? finalData['stems'] as Map<String, dynamic>? ?? {};
      
      Map<String, String> stems = {};
      streamsRaw.forEach((key, value) {
        if (value is String) {
          // If the backend already returns a full URL (starts with http), use it.
          // Otherwise, concatenate with discovery results for legacy support.
          stems[key] = value.startsWith('http') ? value : '$baseUrl$value';
        }
      });

      client.close();
      return SeparationResult(taskId: taskId, stems: stems);
    } catch (e) {
      debugPrint('CloudEngine: Network Error - $e');
      return null;
    }
  }

  Map<String, dynamic> _mapLegacyToHls(List<dynamic> fileList) {
    // Generate a dummy task ID for legacy files
    final taskId = 'legacy-${DateTime.now().millisecondsSinceEpoch}';
    Map<String, String> stems = {};
    
    for (var item in fileList) {
      if (item is Map && item.containsKey('orig_name')) {
        final name = (item['orig_name'] as String).replaceFirst('.wav', '').toLowerCase();
        final url = item['url'] as String?;
        if (url != null) stems[name] = url;
      }
    }
    
    return {
      "task_id": taskId,
      "stems": stems
    };
  }

  Future<Map<String, dynamic>> fetchAdvancedMetrics(String serverPath) async {
    try {
      await _ensureWorkingUrl();
      debugPrint('CloudEngine: Calling analyze_advanced_metrics at $baseUrl...');
      final callUrl = '$baseUrl/gradio_api/call/analyze_advanced_metrics';
      final callPayload = {
        "data": [
          {
            "path": serverPath,
            "meta": {"_type": "gradio.FileData"}
          }
        ]
      };

      final callResponse = await http.post(
        Uri.parse(callUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(callPayload),
      );

      if (callResponse.statusCode != 200) return {"error": "Job creation failed (${callResponse.statusCode})"};

      final eventId = jsonDecode(callResponse.body)['event_id'];
      final streamUrl = '$callUrl/$eventId';
      final client = http.Client();
      final streamResponse = await client.send(http.Request('GET', Uri.parse(streamUrl)));

      List<dynamic>? finalOutputs;
      await for (final line in streamResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          try {
            final json = jsonDecode(line.substring(6));
            if (json is Map && json['msg'] == 'process_completed' && json['output'] != null) {
              finalOutputs = json['output']['data'];
              break;
            }
            if (json is List) {
              finalOutputs = json;
              break;
            }
          } catch (_) {}
        }
      }

      if (finalOutputs == null || finalOutputs.isEmpty) {
        client.close();
        return {"error": "No result received"};
      }

      String clickTrackUrl = '';
      final clickData = finalOutputs[0];
      if (clickData is String) {
        clickTrackUrl = clickData.startsWith('http') ? clickData : '$baseUrl$clickData';
      }

      final structureJson = finalOutputs.length > 1 ? finalOutputs[1] : null;
      client.close();

      return {
        "click_track_url": clickTrackUrl,
        "structure": structureJson
      };
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  Future<Map<String, dynamic>> detectKey(String serverPath) async {
    try {
      await _ensureWorkingUrl();
      debugPrint('CloudEngine: Calling detect_key at $baseUrl...');
      final callUrl = '$baseUrl/gradio_api/call/detect_key';
      final callPayload = {
        "data": [
          {
            "path": serverPath,
            "meta": {"_type": "gradio.FileData"}
          }
        ]
      };

      final callResponse = await http.post(
        Uri.parse(callUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(callPayload),
      );

      if (callResponse.statusCode != 200) return {"error": "Job creation failed (${callResponse.statusCode})"};

      final eventId = jsonDecode(callResponse.body)['event_id'];
      final streamUrl = '$callUrl/$eventId';
      final client = http.Client();
      final streamResponse = await client.send(http.Request('GET', Uri.parse(streamUrl)));

      Map<String, dynamic>? result;
      await for (final line in streamResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          try {
            final json = jsonDecode(line.substring(6));
            List<dynamic>? data;
            if (json is Map && json['msg'] == 'process_completed' && json['output'] != null) {
              data = json['output']['data'];
            } else if (json is List) {
              data = json;
            }

            if (data != null && data.isNotEmpty) {
              final firstResult = data[0];
              if (firstResult is Map && firstResult.containsKey('key_name')) {
                result = Map<String, dynamic>.from(firstResult);
                break;
              }
            }
          } catch (_) {}
        }
      }
      client.close();
      return result ?? {"error": "No result received"};
    } catch (e) {
      return {"error": e.toString()};
    }
  }

  Future<List<dynamic>> extractChords(String serverPath) async {
    try {
      await _ensureWorkingUrl();
      debugPrint('CloudEngine: Calling extract_chords at $baseUrl...');
      final callUrl = '$baseUrl/gradio_api/call/extract_chords';
      final callPayload = {
        "data": [
          {
            "path": serverPath,
            "meta": {"_type": "gradio.FileData"}
          }
        ]
      };

      final callResponse = await http.post(
        Uri.parse(callUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(callPayload),
      );

      if (callResponse.statusCode != 200) return [];

      final eventId = jsonDecode(callResponse.body)['event_id'];
      final streamUrl = '$callUrl/$eventId';
      final client = http.Client();
      final streamResponse = await client.send(http.Request('GET', Uri.parse(streamUrl)));

      List<dynamic>? result;
      await for (final line in streamResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          try {
            final json = jsonDecode(line.substring(6));
            List<dynamic>? data;
            if (json is Map && json['msg'] == 'process_completed' && json['output'] != null) {
              data = json['output']['data'];
            } else if (json is List) {
              data = json;
            }

            if (data != null && data.isNotEmpty) {
               result = data[0] is List ? data[0] : data;
               break;
            }
          } catch (_) {}
        }
      }
      client.close();
      return result ?? [];
    } catch (e) {
      debugPrint('CloudEngine: Chord Error - $e');
      return [];
    }
  }

  Future<void> deleteServerFiles(String taskId) async {
    if (taskId.isEmpty || taskId.startsWith('legacy-')) return;
    try {
      debugPrint('CloudEngine: Fire-and-forget cleanup for Task: $taskId');
      // No await - fire and forget (using dio as requested)
      _dio.delete('$baseUrl/cleanup/$taskId').catchError((e) {
        debugPrint('CloudEngine: Cleanup Error (silently handled)');
        return dio_pkg.Response(requestOptions: dio_pkg.RequestOptions(path: ''));
      });
    } catch (e) {
      debugPrint('CloudEngine: Cleanup Catch (silently handled)');
    }
  }
}
