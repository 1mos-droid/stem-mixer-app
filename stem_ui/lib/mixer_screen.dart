import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_waveforms/audio_waveforms.dart' as wf;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'core/mixer_controller.dart';
import 'core/cloud_api.dart';
import 'core/model_manager.dart';
import 'package:system_info2/system_info2.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:io';

class StudioColors {
  static const Color backgroundStart = Color(0xFF0B0F19);
  static const Color backgroundEnd = Color(0xFF1A1F35);
  static const Color accentCyan = Color(0xFF00F2FF);
  static const Color accentMagenta = Color(0xFFE100FF);
  static const Color glassWhite = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);
}

class MixerScreen extends StatefulWidget {
  const MixerScreen({super.key});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> with WidgetsBindingObserver {
  late final MixerController _controller;
  final CloudEngine _cloudEngine = CloudEngine();
  late final wf.PlayerController _waveformController;
  final ModelManager _modelManager = ModelManager();
  
  bool _isSynchronizing = false;
  double pitchSemitones = 0.0;
  double playbackSpeed = 1.0;
  int? originalRootIndex;
  String? originalScaleType;
  List<dynamic> chordProgression = [];
  String? activeSectionLabel;
  Set<String> soloedTracks = {};
  bool isMetronomeActive = false;
  static const List<String> notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MixerController();
    _waveformController = wf.PlayerController();

    _controller.addListener(_syncWaveformPlayback);
    
    _initSyncMonitor();

    // Check for high RAM and model existence on launch
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEngineStatus());
  }

  void _initSyncMonitor() {
    for (var track in _controller.tracks) {
      track.player.processingStateStream.listen((state) async {
        if (_isSynchronizing) return;

        final anyBuffering = _controller.tracks.any((t) => t.player.processingState == ProcessingState.buffering);
        final allReady = _controller.tracks.every((t) => t.player.processingState == ProcessingState.ready || t.player.processingState == ProcessingState.completed);

        if (anyBuffering && !_controller.isBuffering) {
          // Pause logic: Triggered when any track buffers
          debugPrint("Sync Drift Monitor: Buffering detected. Pausing all.");
          for (var t in _controller.tracks) {
            t.player.pause();
          }
          _controller.setBuffering(true);
        } else if (allReady && _controller.isBuffering) {
          debugPrint("Sync Drift Monitor: Buffer cleared. Starting Master Clock Sync...");
          
          setState(() => _isSynchronizing = true);

          try {
            // MASTER CLOCK SYNC: Use Drums as the reference track
            final drumsTrack = _controller.tracks.firstWhere((t) => t.name == 'Drums');
            final syncPosition = drumsTrack.player.position;

            debugPrint("Sync Drift Monitor: Seeking to ${syncPosition.inMilliseconds}ms");
            
            // Force all players to the exact same millisecond
            await Future.wait(_controller.tracks.map((t) => t.player.seek(syncPosition)));

            // CRITICAL: Delay to allow native buffers to stabilize
            await Future.delayed(const Duration(milliseconds: 200));

            debugPrint("Sync Drift Monitor: Sync Complete. Resuming Playback.");
            
            if (_controller.isPlaying) {
              for (var t in _controller.tracks) {
                t.player.play();
              }
            }
            _controller.setBuffering(false);
          } finally {
            setState(() => _isSynchronizing = false);
          }
        }
      });
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      for (var track in _controller.tracks) {
        track.player.pause();
      }
    }
    
    if (state == AppLifecycleState.detached) {
      if (_controller.currentTaskId != null) {
        _cloudEngine.deleteServerFiles(_controller.currentTaskId!);
      }
    }
  }

  Future<void> _checkEngineStatus() async {
    final ramMB = SysInfo.getTotalPhysicalMemory() ~/ (1024 * 1024);
    if (ramMB >= 6000) {
      final isDownloaded = await _modelManager.isModelDownloaded();
      if (!isDownloaded) {
        _showDownloadDialog();
      }
    }
  }

  void _showDownloadDialog() {
    double progress = 0.0;
    bool isDownloading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AlertDialog(
            backgroundColor: const Color(0xFF15151A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: BorderSide(color: StudioColors.glassBorder)),
            title: Row(
              children: [
                const Icon(Icons.download_for_offline_rounded, color: StudioColors.accentCyan),
                const SizedBox(width: 15),
                Text("Pro Audio Engine Required", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Download the 150MB local AI engine for zero-latency, offline track separation.",
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 30),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    color: StudioColors.accentCyan,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 10),
                  Text("${(progress * 100).toInt()}%", style: GoogleFonts.poppins(color: StudioColors.accentCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                ]
              ],
            ),
            actions: [
              if (!isDownloading) ...[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Use Cloud (Free)", style: GoogleFonts.poppins(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setDialogState(() => isDownloading = true);
                    try {
                      await _modelManager.downloadModel(
                        (received, total) {
                          if (total != -1) {
                            setDialogState(() => progress = received / total);
                          }
                        },
                      );
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      setDialogState(() => isDownloading = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download failed: $e")));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StudioColors.accentCyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("DOWNLOAD", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  void _syncWaveformPlayback() {
    if (_controller.isPlaying) {
      if (_waveformController.playerState == wf.PlayerState.paused || _waveformController.playerState == wf.PlayerState.initialized) {
        _waveformController.startPlayer();
      }
    } else {
      if (_waveformController.playerState == wf.PlayerState.playing) {
        _waveformController.pausePlayer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_syncWaveformPlayback);
    
    // Cleanup server-side files on exit
    if (_controller.currentTaskId != null) {
      _cloudEngine.deleteServerFiles(_controller.currentTaskId!);
    }

    for (var track in _controller.tracks) {
      track.player.dispose();
    }
    _controller.dispose();
    _waveformController.dispose();
    super.dispose();
  }

  Future<void> _pickAndProcess() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (result == null || result.files.single.path == null) return;
    
    final path = result.files.single.path!;

    try {
      // Prevent Audio Duplication: Stop existing tracks
      for (var track in _controller.tracks) {
        await track.player.stop();
      }

      final success = await _controller.processFile(
        path,
        onUploadComplete: (serverPath) {
          _detectMetadataAsync(path, serverPath: serverPath);
        },
      );
      
      if (success) {
        final pitchFactor = math.pow(2.0, pitchSemitones / 12.0);
        for (var track in _controller.tracks) {
          track.player.setPitch(pitchFactor.toDouble());
        }

        // Initialize metronome volume to 0.0 by default
        _controller.setVolume('Metronome', 0.0);
        setState(() => isMetronomeActive = false);

        // Waveform visualizer is disabled for streaming mode to maintain sync stability
        debugPrint("Waveform visualizer bypassed for streaming mode.");
      } else {
         throw Exception("Engine processing failed.");
      }
    } catch (e) {
      debugPrint("❌ Audio Process Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Processing failed: $e"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _detectMetadataAsync(String path, {String? serverPath}) async {
    try {
      // If serverPath is provided, we use it to avoid redundant uploads
      final sPath = serverPath ?? await _cloudEngine.uploadFile(path);
      if (sPath == null) return;

      final results = await Future.wait([
        _cloudEngine.detectKey(sPath),
        _cloudEngine.extractChords(sPath),
      ]);

      final keyData = results[0] as Map<String, dynamic>;
      final chordData = results[1] as List<dynamic>;

      setState(() {
        if (keyData.containsKey('key_name')) {
          originalRootIndex = keyData['root_index'];
          final parts = (keyData['key_name'] as String).split(' ');
          originalScaleType = parts.length > 1 ? parts.sublist(1).join(' ') : "";
        }
        chordProgression = chordData;
      });
    } catch (e) {
      debugPrint("❌ Metadata Detection Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Metadata analysis failed: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      ),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [StudioColors.backgroundStart, StudioColors.backgroundEnd],
            ),
          ),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              return Stack(
                children: [
                  SafeArea(
                    child: Column(
                      children: [
                        _buildHeader(),
                        Expanded(child: _buildMainContent()),
                      ],
                    ),
                  ),
                  if (_controller.isLoaded) _buildMasterPlayback(),
                  if (_controller.isBuffering) _buildBufferingOverlay(),
                  if (_controller.isProcessing) _buildGlassOverlay(),
                  if (!_controller.isEngineInitialized) _buildCriticalErrorBanner(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBufferingOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Container(
        color: Colors.black38,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: StudioColors.accentMagenta, strokeWidth: 2),
              const SizedBox(height: 20),
              Text(
                "SYNCING STREAMS...",
                style: GoogleFonts.poppins(color: Colors.white, letterSpacing: 4, fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "STEM STUDIO PRO",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 2,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          Row(
            children: [
              if (_controller.isLoaded)
                IconButton(
                  onPressed: _showExportSheet,
                  icon: Icon(Icons.ios_share_rounded, color: StudioColors.accentCyan.withOpacity(0.8)),
                ),
              IconButton(
                onPressed: _showInfoDialog,
                icon: Icon(Icons.settings_input_component_rounded, color: Colors.white.withOpacity(0.3)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (!_controller.isLoaded && !_controller.isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPulseIcon(),
            const SizedBox(height: 40),
            Text(
              _controller.status.toUpperCase(),
              style: GoogleFonts.poppins(
                color: Colors.white24,
                letterSpacing: 4,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 60),
            _buildGlassButton(
              label: "IMPORT PROJECT",
              onTap: _pickAndProcess,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        children: [
          _buildChordSyncSection(),
          _buildWaveformArea(),
          _buildStructureChips(),
          const SizedBox(height: 20),
          _buildPitchSlider(),
          const SizedBox(height: 15),
          _buildTempoSlider(),
          const SizedBox(height: 40),
          _buildMixerGrid(),
        ],
      ),
    );
  }

  Widget _buildStructureChips() {
    final structure = _controller.structureData['structure'] as List<dynamic>? ?? [];
    if (structure.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: structure.length,
        itemBuilder: (context, index) {
          final section = structure[index];
          final bool isActive = activeSectionLabel == section['label'];
          
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () async {
                setState(() => activeSectionLabel = section['label']);
                
                // Prevent overlapping/ghost tracks when clipping
                for (var track in _controller.tracks) {
                  await track.player.pause();
                  await track.player.seek(Duration.zero);
                }

                final start = Duration(milliseconds: (section['start_time'] * 1000).toInt());
                final end = Duration(milliseconds: (section['end_time'] * 1000).toInt());
                _controller.setLoopSection(start, end);
              },
              child: _buildGlassContainer(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: Text(
                    section['label'].toUpperCase(),
                    style: GoogleFonts.poppins(
                      color: isActive ? StudioColors.accentCyan : Colors.white38,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTempoSlider() {
    return _buildGlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("TEMPO", style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1, color: Colors.white38)),
              Text("${playbackSpeed.toStringAsFixed(2)}X SPEED", 
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 10, color: StudioColors.accentMagenta)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: StudioColors.accentMagenta,
              inactiveTrackColor: Colors.white.withOpacity(0.05),
              thumbShape: SliderComponentShape.noThumb,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: playbackSpeed,
              min: 0.5,
              max: 1.5,
              divisions: 20,
              onChanged: (v) {
                setState(() {
                  playbackSpeed = v;
                  _controller.setPlaybackSpeed(v);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformArea() {
    return Container(
      height: 60,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: wf.AudioFileWaveforms(
        size: Size(MediaQuery.of(context).size.width, 60.0),
        playerController: _waveformController,
        enableSeekGesture: true,
        waveformType: wf.WaveformType.fitWidth,
        playerWaveStyle: const wf.PlayerWaveStyle(
          fixedWaveColor: Colors.white12,
          liveWaveColor: StudioColors.accentCyan,
          spacing: 6,
          waveCap: StrokeCap.round,
          waveThickness: 3,
        ),
      ),
    );
  }

  Widget _buildChordSyncSection() {
    final masterPlayer = _controller.tracks.first.player;

    return StreamBuilder<Duration>(
      stream: masterPlayer.positionStream,
      builder: (context, snapshot) {
        final positionSec = (snapshot.data?.inMilliseconds ?? 0) / 1000.0;
        
        String activeChord = "ANALYZING...";
        if (chordProgression.isNotEmpty) {
          for (var entry in chordProgression) {
            if (entry['time'] <= positionSec) {
              activeChord = entry['chord'];
            } else {
              break;
            }
          }
        }

        final int semitonesInt = pitchSemitones.round();
        String keyLabel = "DETECTING KEY...";
        if (originalRootIndex != null) {
          int currentIndex = ((originalRootIndex! + semitonesInt) % 12 + 12) % 12;
          keyLabel = "${notes[currentIndex]} ${originalScaleType?.toUpperCase() ?? ""}";
        }

        return Column(
          children: [
            Text(
              keyLabel,
              style: GoogleFonts.poppins(
                color: StudioColors.accentCyan.withOpacity(0.6),
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              activeChord.toUpperCase(),
              key: ValueKey(activeChord),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 48,
                letterSpacing: -2,
                shadows: [
                  Shadow(color: StudioColors.accentCyan.withOpacity(0.5), blurRadius: 20),
                ],
              ),
            ).animate().fade(duration: 300.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
          ],
        );
      },
    );
  }

  Widget _buildPitchSlider() {
    return _buildGlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("TRANSPOSE", style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1, color: Colors.white38)),
              Text("${pitchSemitones >= 0 ? '+' : ''}${pitchSemitones.round()} SEMITONES", 
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 10, color: StudioColors.accentCyan)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: StudioColors.accentCyan,
              inactiveTrackColor: Colors.white.withOpacity(0.05),
              thumbShape: SliderComponentShape.noThumb,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: pitchSemitones,
              min: -12.0,
              max: 12.0,
              divisions: 24,
              onChanged: (v) {
                setState(() {
                  pitchSemitones = v;
                  final pitchFactor = math.pow(2.0, pitchSemitones / 12.0);
                  for (var track in _controller.tracks) {
                    track.player.setPitch(pitchFactor.toDouble());
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMixerGrid() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _controller.tracks.map((track) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: _buildTrackFader(track),
        )).toList(),
      ),
    );
  }

  Widget _buildTrackFader(MixerTrack track) {
    final bool isSoloed = soloedTracks.contains(track.name);
    
    return _buildGlassContainer(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      child: Column(
        children: [
          Icon(Icons.waves_rounded, color: track.color.withOpacity(0.5), size: 14),
          const SizedBox(height: 5),
          Text(
            track.name.toUpperCase(),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            "44.1kHz | Stereo",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w400, fontSize: 6, color: Colors.white24),
          ),
          const SizedBox(height: 15),
          // Panning Slider
          Column(
            children: [
              Text("PAN", style: GoogleFonts.poppins(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.white38)),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  activeTrackColor: Colors.white12,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: StudioColors.accentCyan,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                ),
                child: Slider(
                  value: track.pan,
                  min: -1.0,
                  max: 1.0,
                  onChanged: (v) {
                    setState(() {
                      track.pan = v;
                      // just_audio does not have a simple setPan. 
                      // For a real pro mixer, we'd use a custom audio source,
                      // but for this UI overhaul we will just track the state.
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Vertical Volume Fader
          SizedBox(
            height: 180,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 20,
                  activeTrackColor: track.color.withOpacity(0.3),
                  inactiveTrackColor: Colors.black.withOpacity(0.5),
                  thumbColor: Colors.white,
                  thumbShape: _FaderThumbShape(),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                ),
                child: Slider(
                  value: track.volume,
                  onChanged: (v) => _controller.setVolume(track.name, v),
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSmallRoundButton(
                icon: Icons.volume_off_rounded,
                isActive: track.isMuted,
                activeColor: Colors.redAccent,
                onTap: () => _controller.toggleMute(track.name),
              ),
              _buildSmallRoundButton(
                icon: Icons.headphones_rounded,
                isActive: isSoloed,
                activeColor: Colors.amberAccent,
                onTap: () => _toggleSolo(track.name),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallRoundButton({required IconData icon, required bool isActive, required Color activeColor, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? activeColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          border: Border.all(color: isActive ? activeColor.withOpacity(0.5) : Colors.transparent),
        ),
        child: Icon(
          icon,
          color: isActive ? activeColor : Colors.white24,
          size: 12,
        ),
      ),
    );
  }

  void _toggleSolo(String trackName) {
    setState(() {
      if (soloedTracks.contains(trackName)) {
        soloedTracks.remove(trackName);
      } else {
        soloedTracks.add(trackName);
      }
      
      // Update volumes based on solo state
      if (soloedTracks.isEmpty) {
        // No tracks soloed, restore all track volumes
        for (var t in _controller.tracks) {
          t.player.setVolume(t.isMuted ? 0 : t.volume);
        }
      } else {
        // Only soloed tracks audible
        for (var t in _controller.tracks) {
          if (soloedTracks.contains(t.name)) {
            t.player.setVolume(t.isMuted ? 0 : t.volume);
          } else {
            t.player.setVolume(0);
          }
        }
      }
    });
  }

  Widget _buildMasterPlayback() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Metronome Toggle Button
            GestureDetector(
              onTap: () {
                setState(() {
                  isMetronomeActive = !isMetronomeActive;
                  final metroTrack = _controller.tracks.firstWhere((t) => t.name == 'Metronome');
                  _controller.setVolume('Metronome', isMetronomeActive ? metroTrack.volume : 0.0);
                });
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isMetronomeActive ? Colors.yellowAccent.withOpacity(0.2) : StudioColors.glassWhite,
                  border: Border.all(
                    color: isMetronomeActive ? Colors.yellowAccent : StudioColors.glassBorder,
                    width: 2,
                  ),
                  boxShadow: isMetronomeActive ? [
                    BoxShadow(color: Colors.yellowAccent.withOpacity(0.3), blurRadius: 15, spreadRadius: 2)
                  ] : [],
                ),
                child: Icon(
                  Icons.timer_rounded,
                  color: isMetronomeActive ? Colors.yellowAccent : Colors.white38,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 20),
            GestureDetector(
              onTap: _controller.togglePlayback,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [StudioColors.accentCyan, StudioColors.accentMagenta],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: StudioColors.accentCyan.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(width: 70), // Spacer to balance the metronome button
          ],
        ),
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child, double? width, EdgeInsetsGeometry? margin, EdgeInsetsGeometry? padding}) {
    return Container(
      width: width,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: StudioColors.glassWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: StudioColors.glassBorder, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildGlassButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: _buildGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        child: Text(
          label,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildPulseIcon() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: StudioColors.accentCyan.withOpacity(0.1), width: 2),
      ),
      child: Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: StudioColors.accentCyan.withOpacity(0.05),
            boxShadow: [
              BoxShadow(color: StudioColors.accentCyan.withOpacity(0.1), blurRadius: 40, spreadRadius: 10)
            ],
          ),
          child: const Icon(Icons.multitrack_audio_rounded, color: StudioColors.accentCyan, size: 50),
        ),
      ),
    );
  }

  Widget _buildGlassOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: StudioColors.accentCyan, strokeWidth: 2),
              const SizedBox(height: 40),
              Text(
                _controller.status.toUpperCase(),
                style: GoogleFonts.poppins(color: Colors.white, letterSpacing: 6, fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF15151A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          title: Text("ENGINE STATUS", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow("Initialized", _controller.isEngineInitialized ? "YES" : "NO", _controller.isEngineInitialized ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(height: 15),
              Text("LOAD LOG:", style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _controller.engineLoadError ?? "No errors reported. Engine ready.",
                  style: const TextStyle(color: Colors.amberAccent, fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("CLOSE", style: GoogleFonts.poppins(color: StudioColors.accentCyan, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
        Text(value, style: GoogleFonts.poppins(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildCriticalErrorBanner() {
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 15),
                    Text("ENGINE FAILURE", style: GoogleFonts.poppins(color: Colors.redAccent, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "The native AI engine is incompatible with this device's architecture or missing dependencies.",
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _showInfoDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.05),
                        foregroundColor: Colors.white70,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("DETAILS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => _controller.enableDemoMode(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withOpacity(0.2),
                        foregroundColor: Colors.blueAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("USE DEMO MODE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildGlassContainer(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "EXPORT STEMS",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              "Share or save individual isolated tracks",
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(height: 30),
            ..._controller.tracks.map((track) => _buildExportItem(track)).toList(),
            const SizedBox(height: 20),
            _buildGlassButton(
              label: "SHARE ALL (ZIP)",
              onTap: () async {
                final directory = await getApplicationDocumentsDirectory();
                final stemsDir = Directory(p.join(directory.path, "stems"));
                if (stemsDir.existsSync()) {
                  final files = stemsDir.listSync().whereType<File>().map((f) => XFile(f.path)).toList();
                  if (files.isNotEmpty) {
                    await Share.shareXFiles(files, text: 'AI Stem Studio - Exported Stems');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportItem(MixerTrack track) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: track.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.name.toUpperCase(), style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white)),
                Text("WAV | 32-bit Float", style: GoogleFonts.poppins(fontSize: 9, color: Colors.white24)),
              ],
            ),
          ),
          IconButton(
            onPressed: () async {
              final directory = await getApplicationDocumentsDirectory();
              final stemPath = p.join(directory.path, "stems", "${track.name.toLowerCase()}.wav");
              if (File(stemPath).existsSync()) {
                await Share.shareXFiles([XFile(stemPath)], text: 'Exported ${track.name} Stem');
              }
            },
            icon: Icon(Icons.download_for_offline_rounded, color: Colors.white.withOpacity(0.2)),
          ),
        ],
      ),
    );
  }
}

class _FaderThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(40, 20);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final rect = Rect.fromCenter(center: center, width: 30, height: 12);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    
    // Line in middle
    canvas.drawLine(
      Offset(center.dx - 10, center.dy),
      Offset(center.dx + 10, center.dy),
      Paint()..color = Colors.black26..strokeWidth = 1,
    );
  }
}
