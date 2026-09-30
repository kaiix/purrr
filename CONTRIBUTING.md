# Contributing

Purrr is a small macOS-only prototype. Keep contributions focused on Dictate, Translate, reliable shortcuts, safe text delivery, and retryable local history. Discuss major features or new speech providers in an issue before implementation; a general assistant, cross-platform layer, and speculative provider framework are outside the current scope.

## Development

Follow the toolchain and build instructions in [README.md](README.md). No speech or LLM credentials are required to compile the app. For a development build with no personal signing identity:

```bash
PURRR_CODESIGN_IDENTITY=- Scripts/package_app.sh debug
```

Run `Scripts/compile_and_run.sh` for interactive work. macOS permissions and live-provider behavior need manual checks; compilation alone does not verify them. Keep the app at a stable path and use a stable signing identity when testing permissions.

The build scripts automatically select the first available Apple Development signing identity, falling back to ad-hoc signing. To select an identity or skip signing:

```bash
PURRR_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/compile_and_run.sh
PURRR_CODESIGN_IDENTITY= Scripts/package_app.sh debug
```

Rust dependencies are pinned by `Cargo.lock`; normal builds use `--locked`. The speech bridge requires an installed static Opus library discoverable through pkg-config. Include the native Opus version when reporting build issues, since `Cargo.lock` does not pin it.

GitHub Actions checks formatting and packaged release builds on Apple Silicon without speech credentials, API keys, or a personal signing identity. It does not verify live recognition, text delivery, or macOS permissions.

## Before Submitting

```bash
git diff --check
swift format lint --recursive Sources/Purrr
cargo fmt --manifest-path Rust/PurrrSpeechBridge/Cargo.toml --check
PURRR_CODESIGN_IDENTITY=- Scripts/package_app.sh
codesign --verify --deep --strict build/Purrr.app
```

Describe the change, its scope, and the checks performed. Include relevant macOS and toolchain versions for build bugs. For changes to recording, shortcuts, delivery, permissions, or history, describe the manual regression checks as well. The project currently has no automated end-to-end suite.

Write all code, comments, UI copy, and documentation in English. Preserve the narrow `SpeechEngine` and `TextProcessor` boundaries without adding unused abstractions. Use concise Conventional Commits subjects for commits.

Do not commit API keys, recordings, transcripts, device-registration caches, signing certificates, private-key files, local filesystem paths, or generated build products. Examples must use synthetic data.

## License

Contributions are accepted under Purrr's [MIT License](LICENSE). Ensure you have the right to contribute the material under these terms, and preserve any applicable third-party notices. This does not transfer your copyright to the maintainer.
