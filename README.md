# 🎚️ STEM STUDIO PRO

[![License: PolyForm Noncommercial](https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![C++](https://img.shields.io/badge/C++-%2300599C.svg?style=flat&logo=c%2B%2B&logoColor=white)](https://isocpp.org/)
[![AI-Powered](https://img.shields.io/badge/AI--Powered-ONNX-orange.svg)](https://onnxruntime.ai/)

**Stem Studio Pro** is a professional-grade audio separation and music analysis workstation. Designed for musicians, producers, and researchers, it bridges the gap between high-performance native inference and cloud-scale AI processing.

---

## 🚀 Key Features

### 🌈 Hybrid Separation Engine
*   **Local AI Power:** Zero-latency, offline separation using a quantized **ONNX Demucs** model (optimized for ARM64).
*   **Cloud Pro Suite:** High-fidelity **6-stem separation** (Vocals, Drums, Bass, Piano, Guitar, Other) for the most demanding audio projects.
*   **HLS Streaming:** Efficient delivery of cloud-processed stems via HTTP Live Streaming.

### 🎼 Advanced Music Theory Suite
*   **AI Key Detection:** Instantly identify the root key and scale of any track with high precision.
*   **Live Chord Extraction:** Real-time chord progression mapping synchronized perfectly with playback.
*   **Smart Transposition:** High-fidelity pitch shifting that automatically tracks key changes.

### 📐 Structural Song Mapping
*   **Segment Analysis:** AI-driven identification of song sections (Intro, Verse, Chorus, Bridge, Outro).
*   **Instant Navigation:** One-tap looping and navigation between song structural boundaries.
*   **Metronome Generation:** Synchronized AI click tracks generated based on extracted tempo.

---

## 🏗️ Architecture

| Component | Technology | Responsibility |
| :--- | :--- | :--- |
| **`core_engine/`** | C++, FFmpeg, ONNX Runtime | Native inference, high-speed audio decoding, and FFI bindings. |
| **`stem_ui/`** | Flutter, Dart | Glassmorphic UI, multi-track mixing, and real-time visualization. |
| **`cloud_backend/`** | Python, FastAPI, Librosa, Demucs | 6-stem separation, HLS conversion, and deep music analysis. |
| **`model_builder/`** | PyTorch, ONNX | Training and exporting optimized AI models for mobile devices. |

---

## 🛠️ Getting Started

### 📋 Prerequisites
*   **Flutter SDK** (3.x or higher)
*   **Android NDK** (for building the native C++ engine)
*   **Python 3.10+** (for the cloud backend)

### 🏗️ Building the Android App
To build a lean, performance-optimized ARM64 APK:
```bash
cd stem_ui
chmod +x build_lite.sh
./build_lite.sh
```

### ☁️ Running the Backend
```bash
cd cloud_backend
pip install -r requirements.txt
python app.py
```

---

## 🔒 Security & Privacy

*   **Local-First:** When using the local engine, your audio stays private and never leaves your device.
*   **Public API Ready:** Cloud features use a public Gradio-based API; no complex key management required for standard use.
*   **Optimized Pipelines:** Production builds are sanitized to remove debug symbols and internal paths.

---

## ⚖️ License & Commercial Use

This project is licensed under the **PolyForm Noncommercial License 1.0.0**.

**⚠️ IMPORTANT NOTICE:**
This audio engine is available for **personal and non-commercial research only**. 
*   For commercial use, integration into proprietary DAWs, or SaaS deployment, you **must** purchase a commercial license. 
*   Contact **[isemuk8@gmail.com]** for pricing and licensing inquiries.

See the full [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Developer
For technical inquiries, custom integrations, or collaboration opportunities, feel free to reach out via the email listed above.

*Built with ❤️ for the music community.*
