# STEM STUDIO PRO

# **Licensing & Commercial Use**

**This audio engine is available for personal and non-commercial research. For commercial use, integration into proprietary DAWs, or SaaS deployment, you must purchase a commercial license. Contact [isemuk8@gmail.com] for pricing.**

---

## Overview

Stem Studio Pro is a high-performance audio separation and analysis application. It combines a native C++ inference engine with a cloud-based "Pro Suite" to provide professional-grade stem separation, music theory analysis, and structural song mapping.

## Features

### 1. Hybrid Separation Engine
*   **Local AI Engine:** Uses a quantized ONNX Demucs model for zero-latency, offline separation on high-end devices (ARM64 optimized).
*   **Cloud Pro Suite:** Leverages a high-fidelity 6-stem model (Vocals, Drums, Bass, Other, Piano, Guitar) for complex arrangements.

### 2. Music Theory Suite
*   **Key Detection:** Automatically identifies the musical key and scale of any track.
*   **Chord Extraction:** Real-time chord progression mapping synchronized with audio playback.
*   **Smart Transposition:** High-quality pitch shifting that keeps track of the modified key.

### 3. Structural Song Mapping
*   **AI Song Structure:** Automatically identifies 4-5 major structural boundaries (Intro, Verse, Chorus, etc.).
*   **Smart Looping:** Instant navigation and looping of specific song sections.
*   **Metronome Generation:** AI-generated click tracks synchronized to the song's tempo.

## Architecture

*   **`core_engine/`**: The native C++ core. Handles high-performance audio decoding (FFmpeg), AI inference (ONNX Runtime), and FFI bindings for Flutter.
*   **`stem_ui/`**: The Flutter-based frontend. Features a modern, glassmorphic UI with real-time waveform visualization and multi-track mixing.
*   **`cloud_backend/`**: A Gradio-based API for handling high-fidelity separation and advanced music metrics.

## Security & Privacy

*   **Public API:** The app uses a public Gradio API for cloud features. No private API keys are required for standard operation.
*   **Local Processing:** When the local engine is used, audio data never leaves your device.
*   **Sanitized Build:** Optimized build pipelines ensure no debug symbols or sensitive internal paths are leaked in the production binary.

## Getting Started

### Prerequisites
*   Flutter SDK (3.x+)
*   Android NDK (for native engine compilation)
*   FFmpeg libraries (included in `jniLibs`)

### Build for Android (Optimized)
To build a lean, performance-optimized arm64 APK:
```bash
cd stem_ui
chmod +x build_lite.sh
./build_lite.sh
```

## Developer
For technical inquiries or custom integrations, please reach out via the contact information in the Licensing section.
