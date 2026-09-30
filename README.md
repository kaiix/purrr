# Purrr

Purrr is an experimental macOS menu bar app for dictating and translating speech into the app you are using. Start and stop recording with a keyboard shortcut, then have the result pasted into the original text field.

Dictate returns the recognized text, with optional LLM cleanup. Translate converts it to English or Simplified Chinese using your own OpenAI-compatible API key. Audio and transcript history are kept on your Mac for 24 hours, with copy, retry, and delete actions.

Purrr is available as source code only. Build it locally using the instructions below.

## Requirements

- macOS 14 or later
- Apple Silicon Mac
- Swift 6.2 or later
- Rust 1.88 or later
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

Build and launch the app:

```bash
Scripts/compile_and_run.sh
```

The script creates and launches `build/Purrr.app`. It uses an Apple Development signing identity when available, otherwise ad-hoc signing. Rebuilding with a different signing identity may require granting macOS permissions again. See [CONTRIBUTING.md](CONTRIBUTING.md) for signing overrides and development checks.

To build without launching:

```bash
Scripts/package_app.sh
```

## First Run

1. Purrr opens Settings automatically on first launch. You can reopen it from the menu bar.
2. In Settings, choose **Request Access** for Microphone and approve the macOS prompt.
3. Grant Accessibility permission for automatic text insertion and global shortcuts.
4. To use text cleanup or translation, enable LLM processing, enter an OpenAI-compatible Base URL and API key, and load and select a model. For Translate, choose English or Simplified Chinese as the target language. You can also edit the Dictate and Translate prompts.
5. Press `Option-Space` to start Dictate and press it again to finish.
6. Press `Option-Shift-Space` to start Translate and press it again to finish.

Both shortcuts are customizable in Settings. Press `Escape` to cancel recording. Recordings are limited to nine minutes.

LLM processing is off by default. With it off, Dictate returns the original transcript and Translate is unavailable.

## Limitations and Privacy

Speech recognition requires an internet connection: microphone audio is sent to Doubao IME through an unofficial integration based on [Koe](https://github.com/missuo/koe). This is not an offline recognizer or the public Volcengine ASR API, and service changes may break recognition.

When LLM processing is used, transcripts are sent to your configured API provider. The API key is stored in macOS Keychain. Local history expires after 24 hours; expired entries are removed on launch and periodically while the app runs. See [PRIVACY.md](PRIVACY.md) for storage locations, remote processing, and deletion details.

Purrr is not affiliated with Doubao or ByteDance. Its source license does not grant permission to use their services or guarantee provider-side data retention. Review provider terms and policies before use, and do not record sensitive material.

## License

Purrr is licensed under the [MIT License](LICENSE). Third-party dependencies retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Project Documentation

- [Product requirements](docs/requirements.md)
- [Privacy and data flow](PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Binary release checklist](docs/releasing.md)
