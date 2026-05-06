# Building for Android (Physical Phones)

The error you're seeing occurs because the `libstem_engine_ffi.so` currently in the project was built for **Linux x86_64** and depends on system libraries (FFmpeg, ONNX Runtime) that are not present on Android.

Physical phones use the **ARM** architecture (specifically `arm64-v8a`).

## Prerequisites

To run the AI engine on a physical phone, you need prebuilt Android binaries for:
1. **FFmpeg** (libavformat, libavcodec, libavutil, libswresample)
2. **ONNX Runtime**

## Setup Steps

### 1. Obtain Prebuilt Libraries
Download or build the `.so` files for `arm64-v8a`:
- **ONNX Runtime:** Use the [official Android releases](https://github.com/microsoft/onnxruntime/releases).
- **FFmpeg:** Use a prebuilt Android distribution like [ffmpeg-android-maker](https://github.com/Javernaut/ffmpeg-android-maker).

### 2. Place Libraries in `jniLibs`
Place the `.so` files in:
`stem_ui/android/app/src/main/jniLibs/arm64-v8a/`

You should have:
- `libavcodec.so`
- `libavformat.so`
- `libavutil.so`
- `libswresample.so`
- `libonnxruntime.so`

### 3. Build the Engine
The project is now configured to use `externalNativeBuild`. When you run `flutter run` on your phone, Gradle will automatically attempt to compile `core_engine` using the Android NDK.

Ensure your `local.properties` points to your Android NDK path:
`ndk.dir=/path/to/your/android-sdk/ndk/25.x.x`

## Immediate Workaround: Demo Mode
If you want to test the UI without building the native engine, click the **"USE DEMO MODE"** button on the error banner. This will use a mock engine that simulates the separation process.
