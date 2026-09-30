# Product

## Platform

macOS

## Stack

SwiftPM-based native macOS application using Swift, SwiftUI, and AppKit. Audio capture uses native macOS APIs. The first speech engine is Doubao IME behind a narrow engine boundary; a small Rust static-library bridge reuses Koe's protocol implementation.

## Users

Apple Silicon Mac users who want to dictate or translate text directly into the application they are already using.

## Product Purpose

Purrr turns a short voice session into useful text at the current typing destination. Dictate produces either raw recognition or lightly cleaned text. Translate produces a natural English or Simplified Chinese translation. Success means the interaction is faster than switching to a separate transcription tool and safe enough not to paste into the wrong application.

## Positioning

Purrr combines shortcut-first voice input, Doubao IME recognition, optional bring-your-own-key language-model processing, and local retryable history. It is a focused writing utility rather than a general assistant.

## Operating Context

- Purrr runs as a menu bar application without a regular Dock icon.
- The user starts Dictate or Translate with independent global toggle shortcuts while another application's text field is focused.
- A non-activating floating bar communicates recording and processing without showing live transcript text.
- The result is delivered back to the original destination when focus remains safe; otherwise it is copied to the clipboard.
- Audio and transcript history remain local for 24 hours and support copy, retry, individual deletion, and Delete All.

## Capabilities and Constraints

- macOS 14 or later on Apple Silicon only.
- Source-only distribution with local builds; no Mac App Store distribution.
- Dictate and Translate only; no general voice assistant.
- Default shortcuts are `Option-Space` for Dictate and `Option-Shift-Space` for Translate; both are customizable.
- A shortcut toggles recording. `Escape` cancels an active session.
- A recording may last up to nine minutes, with a visible countdown during the final minute.
- The first speech engine is the unofficial Doubao IME protocol, not the public Volcengine ASR API.
- The language model uses a user-provided key with a non-streaming OpenAI-compatible Chat Completions endpoint.
- Language-model processing is optional and defaults to off. Dictate returns raw ASR text while it is off. Translate requires it to be enabled and configured.
- Initial translation targets are English and Simplified Chinese.
- The current system default microphone is used in v1.
- Only Doubao IME recognition is implemented; there is no provider selection or local model management.

## Brand Commitments

- Product name: Purrr.
- The interaction reference is Typeless: quiet, fast, shortcut-first, and visually subordinate to the user's current work.
- All product code and documentation are written in English.

## Project References

- Product requirements: `docs/requirements.md`.
- Design system: `DESIGN.md`.
- Native application packaging: `Scripts/package_app.sh`.
- Speech-engine references: `https://github.com/cjpais/Handy` and `https://github.com/missuo/koe`.
- Original app and menu bar marks: `Assets/`.

## Product Principles

- Make the common voice-to-text path immediate and unobtrusive.
- Preserve user intent; processing may clean language but must not invent content.
- Never paste into an application that did not initiate the session.
- Keep retained voice data local, visible, and automatically short-lived.
- Prefer a small working implementation with narrow replacement points over a generalized provider framework.

## Accessibility & Inclusion

- Core actions must remain keyboard accessible.
- Status cannot rely on color alone.
- Motion should respect the macOS Reduce Motion setting.
- Permission failures must identify the missing permission and provide a recovery path.
