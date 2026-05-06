import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'engine_binding.dart';
import 'cloud_api.dart';

class MixerTrack {
  final String name;
  final AudioPlayer player;
  final Color color;
  double volume = 0.8;
  double pan = 0.0;
  bool isMuted = false;

  MixerTrack({
    required this.name,
    required this.player,
    required this.color,
  });
}

class MixerController extends ChangeNotifier {
  final StemEngine _engine = StemEngine();
  final CloudEngine _cloudEngine = CloudEngine();
  
  final List<MixerTrack> tracks = [
    MixerTrack(name: 'Vocals', player: AudioPlayer(), color: Colors.pinkAccent),
    MixerTrack(name: 'Drums', player: AudioPlayer(), color: Colors.orangeAccent),
    MixerTrack(name: 'Bass', player: AudioPlayer(), color: Colors.purpleAccent),
    MixerTrack(name: 'Piano', player: AudioPlayer(), color: Colors.lightGreenAccent),
    MixerTrack(name: 'Guitar', player: AudioPlayer(), color: Colors.yellowAccent),
    MixerTrack(name: 'Other', player: AudioPlayer(), color: Colors.lightBlueAccent),
    MixerTrack(name: 'Metronome', player: AudioPlayer(), color: Colors.limeAccent),
  ];

  bool _isProcessing = false;
  bool _isLoaded = false;
  bool _isPlaying = false;
  String _status = "Ready to separate";
  Map<String, dynamic> _structureData = {};
  String? _currentTaskId;

  bool get isProcessing => _isProcessing;
  bool get isLoaded => _isLoaded;
  bool get isPlaying => _isPlaying;
  String get status => _status;
  bool get isEngineInitialized => _engine.isInitialized;
  String? get engineLoadError => _engine.loadError;
  Map<String, dynamic> get structureData => _structureData;
  String? get currentTaskId => _currentTaskId;

  @override
  void dispose() {
    for (var track in tracks) {
      track.player.dispose();
    }
    super.dispose();
  }

  bool _isBuffering = false;
  bool get isBuffering => _isBuffering;

  void setBuffering(bool value) {
    if (_isBuffering != value) {
      _isBuffering = value;
      notifyListeners();
    }
  }

  Future<bool> processFile(String inputPath, {Function(String)? onUploadComplete}) async {
    _isProcessing = true;
    _isLoaded = false;
    _status = "Cloud Processing (Pro Suite)...";
    notifyListeners();

    try {
      // Step 1: Upload once
      final serverPath = await _cloudEngine.uploadFile(inputPath);
      if (serverPath == null) {
        _status = "Upload failed.";
        return false;
      }
      
      if (onUploadComplete != null) {
        onUploadComplete(serverPath);
      }

      // Step 2: 6-Stem Separation
      _status = "Separating stems...";
      notifyListeners();
      final stemUrls = await _cloudEngine.separateAudio(serverPath);
      if (stemUrls == null || stemUrls.isEmpty) {
        _status = "Cloud separation failed.";
        return false;
      }

      // Extract Task ID from URLs (format: /static/{task_id}/{stem}/track.m3u8)
      final firstUrl = stemUrls.values.first;
      final uri = Uri.parse(firstUrl);
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments[0] == 'static') {
        _currentTaskId = segments[1];
        debugPrint("MixerController: Detected Task ID: $_currentTaskId");
      }

      // Step 3: Advanced Metrics
      _status = "Analyzing song structure...";
      notifyListeners();
      _structureData = await _cloudEngine.fetchAdvancedMetrics(serverPath);

      _status = "Initializing streams...";
      notifyListeners();
      await _loadStems(stemUrls, _structureData['click_track_url'] ?? '');
      
      _isLoaded = true;
      _status = "Mixer Active";
      return true;
    } catch (e) {
      _status = "Error: $e";
      debugPrint("Process Error: $e");
      rethrow; 
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> _loadStems(Map<String, String> stemUrls, String clickUrl) async {
    try {
      final normalizedUrls = {
        'Vocals': stemUrls['vocals'],
        'Drums': stemUrls['drums'],
        'Bass': stemUrls['bass'],
        'Piano': stemUrls['piano'],
        'Guitar': stemUrls['guitar'],
        'Other': stemUrls['other'],
        'Metronome': clickUrl,
      };

      await Future.wait(tracks.map((track) async {
        final url = normalizedUrls[track.name];
        if (url != null && url.isNotEmpty) {
          await track.player.setAudioSource(
            AudioSource.uri(Uri.parse(url)),
            initialPosition: Duration.zero,
            preload: true,
          );
          await track.player.setVolume(track.isMuted ? 0 : track.volume);
          await track.player.setLoopMode(LoopMode.one);
        }
      }));
      
      await Future.wait(tracks.map((t) => t.player.seek(Duration.zero)));
    } catch (e) {
      debugPrint("Load Error: $e");
      rethrow;
    }
  }

  void togglePlayback() {
    if (_isPlaying) {
      for (var t in tracks) {
        t.player.pause();
      }
    } else {
      // Sync players before play
      final masterPos = tracks.first.player.position;
      for (var t in tracks.skip(1)) {
        t.player.seek(masterPos);
      }
      for (var t in tracks) {
        t.player.play();
      }
    }
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    for (var t in tracks) {
      t.player.setSpeed(speed);
    }
    notifyListeners();
  }

  void setLoopSection(Duration start, Duration end) {
    for (var t in tracks) {
      t.player.setClip(start: start, end: end);
      t.player.setLoopMode(LoopMode.one);
    }
    // Seek to start for immediate effect
    for (var t in tracks) {
      t.player.seek(start);
    }
    notifyListeners();
  }

  void stopPlayback() {
    for (var t in tracks) {
      t.player.stop();
      t.player.seek(Duration.zero);
      t.player.setClip(); // Reset clip
    }
    _isPlaying = false;
    notifyListeners();
  }

  void setVolume(String trackName, double volume) {
    final track = tracks.firstWhere((t) => t.name == trackName);
    track.volume = volume;
    if (!track.isMuted) {
      track.player.setVolume(volume);
    }
    notifyListeners();
  }

  void toggleMute(String trackName) {
    final track = tracks.firstWhere((t) => t.name == trackName);
    track.isMuted = !track.isMuted;
    track.player.setVolume(track.isMuted ? 0 : track.volume);
    notifyListeners();
  }

  void enableDemoMode() {
    _engine.enableMockMode();
    notifyListeners();
  }
}
