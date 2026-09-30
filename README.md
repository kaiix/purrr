# Purrr

Purrr is a focused macOS voice-input prototype. It provides Dictate and Translate modes through global toggle shortcuts, uses the Doubao IME speech-recognition protocol, optionally cleans or translates text with a user-provided OpenAI-compatible API, and keeps retryable local history for 24 hours.

The app's bundle identifier and Keychain service are `io.github.kaiix.purrr`.

## Requirements

- macOS 14 or later
- Apple Silicon Mac
- Swift 6.2 or later
- Rust 1.88 or later (required by the locked dependencies)
- CMake, required by the Opus dependency
- Opus (including its static library) and pkg-config

## Build and Run

Clone the repository and install the Apple Silicon Rust target if necessary:

```bash
git clone https://github.com/kaiix/purrr.git
cd purrr
rustup target add aarch64-apple-darwin
```

Use an Xcode toolchain that provides Swift 6.2 or later. Install native dependencies with `brew install cmake opus pkgconf`. Rust is installed separately through [rustup](https://rustup.rs/).

The bridge statically links the installed Opus library. It requires Opus through pkg-config instead of falling back to the obsolete bundled source in `audiopus_sys`, which fails with CMake 4. `Cargo.lock` pins Rust crates, not the installed native Opus version; include that version when reporting build issues or preparing binary notices.

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

Rust dependencies are pinned by `Cargo.lock`; normal builds use `--locked`. GitHub Actions checks an ad-hoc-signed release build on an Apple Silicon runner without microphone access, API keys, or developer signing credentials. This is a build check, not an end-to-end speech or permissions test.

## First Run

1. Purrr opens Settings automatically on first launch. You can reopen it from the menu bar.
2. In Settings, choose **Request Access** for Microphone. Opening the macOS privacy pane alone does not add a new app to its Microphone list; Purrr must make the system authorization request first.
3. Grant Accessibility permission for safe text insertion and conflict-free global shortcuts. Purrr refreshes this permission while Settings remains open.
4. Optionally enable LLM processing, enter an OpenAI-compatible Base URL and API key, load a model from the endpoint, and customize the Dictate or Translate prompts if needed.
5. Press `Option-Space` to start Dictate and press it again to finish.
6. Press `Option-Shift-Space` to start Translate and press it again to finish.

The API key is stored in macOS Keychain. Audio and transcript history are stored under the user's Application Support directory. Entries expire after 24 hours and are cleaned up at launch and every 30 minutes while Purrr is running. See [PRIVACY.md](PRIVACY.md) for remote processing, local storage, and deletion details.

## Important Prototype Constraint

The Doubao IME integration uses an unofficial private protocol pinned to a known Koe commit. It may stop working when the service changes. It is distinct from the public Volcengine ASR API and should not be presented as a local or offline recognizer.

Purrr is an independent project, not affiliated with Typeless, Doubao, ByteDance, or the referenced projects. The Koe source license does not grant permission to use Doubao's service or establish its data-retention policy. Service availability, terms, and authorization must be assessed separately before deployment. Do not use the current prototype for sensitive recordings.

The current distribution scope is source-only: users clone the repository and build Purrr locally with the instructions above. No prebuilt app, Homebrew package, or automatic-update feed is published. CI builds validate the source but do not distribute app artifacts. Development and ad-hoc signatures are not notarized release signatures.

## License

Purrr is licensed under the [MIT License](LICENSE), copyright 2026 kaiix. Third-party dependencies retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The app bundle includes Purrr's license, but the complete dependency notice bundle remains a prerequisite for public binary distribution.

## Project Documentation

- [Product requirements](docs/requirements.md)
- [Privacy and data flow](PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Binary release checklist](docs/releasing.md)
