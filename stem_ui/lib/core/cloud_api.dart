import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';

class CloudEngine {
  final String baseUrl = 'https://1mos-droid-stem-engine-api.hf.space';

  Future<String?> uploadFile(String inputPath) async {
    try {
      debugPrint('CloudEngine: Uploading audio...');
      final file = File(inputPath);
      if (!await file.exists()) {
        debugPrint('CloudEngine: Error - Input file not found.');
        return null;
      }

      final uploadRequest = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      uploadRequest.files.add(await http.MultipartFile.fromPath(
        'files', 
        inputPath,
        contentType: MediaType('audio', p.extension(inputPath).replaceAll('.', '')),
      ));

      final uploadResponse = await uploadRequest.send();
      if (uploadResponse.statusCode != 200) {
        debugPrint('CloudEngine: Upload failed (${uploadResponse.statusCode})');
        return null;
      }

      final uploadData = jsonDecode(await uploadResponse.stream.bytesToString());
      return uploadData[0]; // The server path
    } catch (e) {
      debugPrint('CloudEngine: Upload Error - $e');
      return null;
    }
  }

  Future<Map<String, String>?> separateAudio(String serverPath) async {
    try {
      debugPrint('CloudEngine: Creating separation job...');
      final callUrl = '$baseUrl/call/separate_audio';
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

      List<dynamic>? finalOutputs;
      await for (final line in streamResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final dataContent = line.substring(6);
          try {
            final json = jsonDecode(dataContent);
            if (json is Map && json['msg'] == 'process_completed' && json['output'] != null) {
              finalOutputs = json['output']['data'];
              break;
            }
            if (json is List) {
              finalOutputs = json;
              break;
            }
            if (json is Map && json.containsKey('data') && json['data'] is List) {
               finalOutputs = json['data'];
               break;
            }
          } catch (_) {}
        }
      }

      if (finalOutputs == null || finalOutputs.isEmpty) {
        debugPrint('CloudEngine: Error - Could not retrieve stems from stream.');
        return null;
      }

      final nonNullOutputs = finalOutputs!;
      final stemNames = ['vocals', 'drums', 'bass', 'other', 'piano', 'guitar'];
      Map<String, String> stemUrls = {};
      
      int count = nonNullOutputs.length < 6 ? nonNullOutputs.length : 6;
      for (int i = 0; i < count; i++) {
        final stemUrl = nonNullOutputs[i];
        if (stemUrl is String) {
          stemUrls[stemNames[i]] = stemUrl.startsWith('http') ? stemUrl : '$baseUrl$stemUrl';
        }
      }

      client.close();
      return stemUrls;
    } catch (e) {
      debugPrint('CloudEngine: Network Error - $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchAdvancedMetrics(String serverPath) async {
    try {
      debugPrint('CloudEngine: Calling analyze_advanced_metrics...');
      final callUrl = '$baseUrl/call/analyze_advanced_metrics';
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
      debugPrint('CloudEngine: Calling detect_key...');
      final callUrl = '$baseUrl/call/detect_key';
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
      debugPrint('CloudEngine: Calling extract_chords...');
      final callUrl = '$baseUrl/call/extract_chords';
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

  void deleteServerFiles(String taskId) {
    if (taskId.isEmpty) return;
    try {
      debugPrint('CloudEngine: Fire-and-forget cleanup for Task: $taskId');
      // No await - fire and forget
      http.delete(Uri.parse('$baseUrl/cleanup/$taskId')).catchError((e) {
        debugPrint('CloudEngine: Cleanup Error (silently handled) - $e');
      });
    } catch (e) {
      debugPrint('CloudEngine: Cleanup Catch (silently handled) - $e');
    }
  }
}
