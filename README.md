# Purrr

Purrr is a focused macOS voice-input prototype. It provides Dictate and Translate modes through global toggle shortcuts, uses the Doubao IME speech-recognition protocol, optionally cleans or translates text with a user-provided OpenAI-compatible API, and keeps retryable local history for 24 hours.

The app's bundle identifier and Keychain service are `io.github.kaiix.purrr`.

## Requirements

- macOS 14 or later
- Apple Silicon Mac
- Swift 6.2 or later
- Rust 1.85 or later
- CMake, required by the Opus dependency

## Build and Run

```bash
Scripts/compile_and_run.sh
```

The script builds the pinned Koe-based Rust speech bridge, builds the SwiftPM executable, assembles `build/Purrr.app`, signs it, registers it with LaunchServices, and launches it. It automatically uses the first available Apple Development identity so macOS can keep TCC permissions associated with the same app identity. Override that choice when needed:

```bash
PURRR_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/compile_and_run.sh
PURRR_CODESIGN_IDENTITY=- Scripts/compile_and_run.sh  # Force ad-hoc signing.
PURRR_CODESIGN_IDENTITY= Scripts/compile_and_run.sh   # Skip signing.
```

To build without launching:

```bash
Scripts/package_app.sh
```

## First Run

1. Purrr opens Settings automatically on first launch. You can reopen it from the menu bar.
2. In Settings, choose **Request Access** for Microphone. Opening the macOS privacy pane alone does not add a new app to its Microphone list; Purrr must make the system authorization request first.
3. Grant Accessibility permission for safe text insertion and conflict-free global shortcuts. Purrr refreshes this permission while Settings remains open.
4. Optionally enable LLM processing, enter an OpenAI-compatible Base URL and API key, load a model from the endpoint, and customize the Dictate or Translate prompts if needed.
5. Press `Option-Space` to start Dictate and press it again to finish.
6. Press `Option-Shift-Space` to start Translate and press it again to finish.

The API key is stored in macOS Keychain. Audio and transcript history are stored under the user's Application Support directory and removed after 24 hours.

## Important Prototype Constraint

The Doubao IME integration uses an unofficial private protocol pinned to a known Koe commit. It may stop working when the service changes. It is distinct from the public Volcengine ASR API and should not be presented as a local or offline recognizer.

See [docs/requirements.md](docs/requirements.md) for the complete v1 requirements.
