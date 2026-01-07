# Whisper.cpp Integration Guide

This guide explains how to build and integrate whisper.cpp with Core ML support into the Homie macOS app.

## Prerequisites

- Xcode with command-line tools installed
- Python 3.11 (recommended via Miniconda)
- macOS Sonoma (14) or newer recommended

## Step 1: Clone whisper.cpp

```bash
git clone https://github.com/ggml-org/whisper.cpp.git ~/Developer/whisper.cpp
cd ~/Developer/whisper.cpp
```

## Step 2: Build the XCFramework

Build whisper.cpp as an XCFramework for Apple platforms:

```bash
./build-xcframework.sh
```

This creates `build-apple/whisper.xcframework`.

> **Note:** If you get "iphoneos is not an iOS SDK" error, run:
> ```bash
> sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
> ```

## Step 3: Download a Model

Download the base English model:

```bash
./models/download-ggml-model.sh base.en
```

This downloads `models/ggml-base.en.bin` (~142MB).

See [available models](https://github.com/ggml-org/whisper.cpp/tree/master/models) for other options.

## Step 4: Core ML Support (Recommended for Apple Silicon)

Core ML enables the Encoder to run on the Apple Neural Engine (ANE), providing ~3x speed improvement.

### Install Python Dependencies

```bash
# Optional: Create a conda environment
conda create -n py311-whisper python=3.11 -y
conda activate py311-whisper

# Install dependencies
pip install ane_transformers
pip install openai-whisper
pip install coremltools
```

### Generate Core ML Model

```bash
./models/generate-coreml-model.sh base.en
```

This creates `models/ggml-base.en-encoder.mlmodelc/` directory.

> **Note:** First run on device is slow as ANE compiles the model. Subsequent runs are faster.

## Step 5: Integrate with Xcode Project

### Add XCFramework

1. Open `homie.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the **homie** target
4. Go to **Build Phases** tab
5. Expand **Embed Frameworks**
6. Click **+** and add `whisper.xcframework` from `~/Developer/whisper.cpp/build-apple/`
7. Ensure "Embed & Sign" is selected

### Add Model Files to Bundle

1. Drag `ggml-base.en.bin` into your Xcode project (e.g., `homie/Resources/models/`)
2. If using Core ML, also drag `ggml-base.en-encoder.mlmodelc/` folder
3. Ensure "Copy items if needed" is checked
4. Ensure files are added to the **homie** target

## Step 6: Code Signing for Distribution

When building for distribution (DMG), the whisper.framework must be signed with the same Team ID as the main app.

Sign the framework once after building:

```bash
codesign --force --deep --sign "Apple Development: your@email.com (TEAM_ID)" \
    ~/Developer/whisper.cpp/build-apple/whisper.xcframework
```

Replace with your actual signing identity. Find it with:
```bash
security find-identity -v -p codesigning
```

> **Important:** Re-sign after each rebuild of whisper.cpp.

## Architecture

### Audio Pipeline
```
Microphone → 48kHz Audio → Resample to 16kHz → whisper.cpp → Text
```

### With Core ML
```
Audio → whisper.cpp (Decoder on CPU) + Core ML (Encoder on ANE) → Text
```

## Performance

| Model | Size | Memory | Speed (Apple Silicon) |
|-------|------|--------|----------------------|
| tiny.en | 75MB | ~200MB | ~10x real-time |
| base.en | 142MB | ~388MB | ~5x real-time |
| small.en | 466MB | ~850MB | ~2x real-time |

Core ML provides additional ~3x speedup for the encoder.

## Troubleshooting

### "Failed to load whisper model"
- Verify `ggml-base.en.bin` is in the app bundle
- Check the file path in your code matches the bundle location

### "Library not loaded" / "different Team IDs"
- Re-sign whisper.xcframework with your Team ID (see Step 6)
- Rebuild the app and DMG

### Core ML model not loading
- Ensure `ggml-base.en-encoder.mlmodelc/` folder is in bundle
- The `.mlmodelc` is a directory, not a single file
- Both ggml model AND Core ML model are required

### Slow first transcription
- Normal for Core ML - ANE compiles the model on first run
- Subsequent runs will be much faster

## References

- [whisper.cpp SwiftUI example](https://github.com/ggml-org/whisper.cpp/tree/master/examples/whisper.swiftui)
- [whisper.cpp Core ML support](https://github.com/ggml-org/whisper.cpp#core-ml-support)
- [Available models](https://github.com/ggml-org/whisper.cpp/tree/master/models)
