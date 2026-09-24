# Purrr v1 Requirements

Status: Initial prototype implemented  
Last updated: 2026-09-22

## 1. Product Summary

Purrr is a small, native macOS voice input application for personal and internal use. It runs in the background, records speech after a global shortcut is pressed, converts the speech into text with Doubao IME, optionally processes the transcript with a user-configured OpenAI-compatible language model, and inserts the result into the previously active text field.

The first version intentionally has a small scope. It should leave clean extension points for future speech engines without implementing a general plugin system, model manager, or provider capability framework.

## 2. Platform Requirements

- macOS 14 or later.
- Apple Silicon only (`arm64`).
- Intel Macs are not supported.
- Native macOS application.
- Internal or personal distribution rather than Mac App Store distribution.
- Package the SwiftPM executable as a native `.app` bundle using `Scripts/package_app.sh`.

## 3. Version 1 Scope

Purrr v1 must provide:

1. Dictate mode.
2. Translate mode.
3. Global keyboard shortcuts.
4. A floating transcription bar that appears when a shortcut starts a session.
5. Doubao IME speech recognition.
6. Optional language-model post-processing through a user-configured OpenAI-compatible API.
7. Automatic delivery of the final result to the text field that was active when recording started.
8. Customizable shortcuts with Typeless-style defaults.
9. Local 24-hour audio and transcript history with copy, retry, and deletion actions.

## 4. Explicit Non-Goals

Purrr v1 does not include:

- Ask Anything or a general voice assistant.
- Operations on selected text.
- Meeting transcription.
- Speaker diarization or word-level timestamps.
- A speech-engine selection UI.
- A local Whisper or SenseVoice implementation.
- A local model downloader or model manager.
- A general plugin system.
- A personal dictionary.
- Per-application writing profiles.
- Mobile or non-macOS clients.
- User accounts, subscriptions, or a Purrr cloud service.

Future local and cloud speech engines remain architectural considerations, not v1 deliverables.

## 5. Core User Flows

### 5.1 Dictate

1. The user focuses a text field in any macOS application.
2. The user presses the Dictate shortcut, `Option-Space`, once.
3. Purrr remembers the destination application and displays the transcription bar.
4. Purrr starts recording and streams audio to Doubao IME.
5. The transcription bar displays an audio waveform driven by microphone input. It does not display interim recognition text.
6. The user presses `Option-Space` again to end the recording.
7. Purrr obtains the final source transcript.
8. If language-model processing is enabled, Purrr sends the transcript to the configured language model. The model removes filler words, repetitions, and false starts; resolves spoken self-corrections; and adds appropriate punctuation and formatting.
9. If language-model processing is disabled, Purrr uses the final transcript returned by Doubao IME without modification.
10. Purrr inserts the resulting text into the original destination.
11. Purrr stores the source transcript and delivered text in local history.

The language model must preserve the user's intended meaning. It must not invent facts, expand the content, or silently change names, numbers, URLs, code, or technical terms.

### 5.2 Translate

1. The user focuses a text field.
2. The user presses the Translate shortcut, `Option-Shift-Space`, once.
3. Purrr requires language-model processing to be enabled and correctly configured. Otherwise, it does not start recording and prompts the user to enable or configure the language model in Settings.
4. Purrr displays the transcription bar and records speech.
5. The transcription bar displays an audio waveform and no interim recognition text.
6. The user presses `Option-Shift-Space` again to end the recording.
7. Doubao IME returns the source-language transcript.
8. Purrr sends the transcript and configured target language to the language model.
9. The model removes speech disfluencies and produces a natural translation while preserving meaning and tone.
10. Purrr inserts the translated text into the original destination.
11. Purrr stores the source transcript and translated text in local history.

Translation should be performed by the language model after speech recognition. Doubao IME remains responsible only for speech recognition.

If the automatically detected source language is the same as the selected target language, Translate still runs language-model cleanup and polishing in that language.

## 6. Session States

The v1 session state machine should remain small:

```text
Idle
  -> Recording
  -> Recognizing
  -> Processing
  -> Delivering
  -> Idle
```

An active session may also enter `Cancelled` or `Failed`.

The transcription bar should communicate these states clearly without taking keyboard focus from the destination application. During recording it displays an audio waveform rather than recognition text. After successful delivery it displays a success state for one second and then disappears.

Pressing `Escape` during an active recording cancels the session. A cancelled session with captured audio is retained as a dismissed history entry, but it does not insert partial text. Silence-only or effectively empty recordings produce no insertion.

## 7. Keyboard Shortcuts and Recording Limit

Purrr uses two independent toggle shortcuts:

- Dictate default: `Option-Space`.
- Translate default: `Option-Shift-Space`.

Pressing a shortcut while idle starts that mode. Pressing the same shortcut again stops recording and starts finalization. Purrr v1 does not require push-to-talk behavior.

While one mode is recording, pressing the other mode's shortcut has no effect. Purrr must not switch modes or start a second session.

Both shortcuts are customizable in Settings. Purrr must prevent the same shortcut from being assigned to both modes, reject unsupported modifier-only combinations, and provide an action to restore the defaults. New shortcut assignments should take effect without restarting the application.

Purrr must consume a recognized shortcut before the foreground application receives it. If another application, such as ChatGPT, has already registered the same global shortcut, Purrr uses an Accessibility-authorized active HID event tap. Carbon hot-key registration remains the lower-permission fallback when no conflict exists.

The maximum duration of one recording is nine minutes, matching Typeless. At eight minutes, the transcription bar must replace or augment the waveform with a visible 60-second countdown. Reaching nine minutes automatically ends recording and continues through recognition and processing as if the user had pressed the shortcut again.

## 8. Minimal Architecture

```text
Global Shortcut
      |
      v
Audio Capture + Destination Capture
      |
      v
DoubaoImeSpeechEngine
      |
      v
Optional OpenAICompatibleTextProcessor
      |
      v
Safe Text Delivery
```

The first version needs only two narrow extension points.

### 8.1 Speech engine

```swift
protocol SpeechEngine: Sendable {
    func start() async throws
    func send(_ audio: AudioChunk) async throws
    func finish() async throws -> String
    func cancel() async
}
```

The only v1 implementation is `DoubaoImeSpeechEngine`.

The protocol should avoid Doubao-specific types so a future implementation can support local Whisper, SenseVoice, OpenAI realtime transcription, Gemini Live transcription, or another engine. Purrr v1 does not need an engine registry, capability negotiation, or local model lifecycle abstraction.

The concrete engine may expose interim transcript updates to the transcription bar through a callback or asynchronous event stream. This does not need to be standardized beyond what v1 requires.

### 8.2 Text processor

```swift
protocol TextProcessor: Sendable {
    func dictate(_ transcript: String) async throws -> String
    func translate(
        _ transcript: String,
        targetLanguage: String
    ) async throws -> String
}
```

The only v1 implementation is `OpenAICompatibleTextProcessor`.

The application workflow decides whether to invoke this processor. When language-model processing is disabled, Dictate bypasses it and Translate is unavailable.

## 9. Doubao IME Integration

Doubao IME is the required v1 speech engine because its recognition behavior differs from the public Volcengine ASR product. Purrr should integrate the Doubao IME protocol rather than replace it with the public Volcengine API.

Expected behavior based on the Koe reference implementation:

- Remote WebSocket recognition.
- PCM signed 16-bit little-endian, mono, 16 kHz input.
- Approximately 20 ms audio frames.
- Automatic device registration.
- Cumulative streaming recognition results.

The returned result may contain a cumulative session transcript and additional per-segment entries. The adapter must treat the cumulative transcript as a replacement snapshot rather than concatenate all entries.

This is an unofficial integration intended for an internal prototype. Its endpoint, authentication, fixed client credential, and result format may change without notice. The Doubao implementation must remain isolated behind `SpeechEngine` so it can be repaired or replaced without changing application workflow code.

Reference:

- <https://github.com/missuo/koe/blob/main/koe-asr/src/doubaoime.rs>

## 10. OpenAI-Compatible Language Model

Purrr uses Bring Your Own Key configuration. It does not proxy requests through a Purrr service.

Required settings:

- Enable language-model processing toggle.
- Base URL.
- API key.
- Model selected from the endpoint's model list.
- Editable Dictate and Translate prompts.
- One target translation language selected in Settings.

The initial target-language list contains:

- English.
- Simplified Chinese.

Source-language recognition remains automatic. Purrr v1 does not require regional variants or additional translation targets.

Requirements:

- The toggle defaults to off on a fresh installation.
- When the toggle is off, Dictate delivers the unmodified Doubao IME transcript and Translate prompts the user to enable language-model processing.
- When the toggle is on, Base URL, API key, and a selected Model must all be configured before starting Dictate or Translate. If configuration is incomplete, Purrr must guide the user to Settings rather than starting a session.
- Load model identifiers with `GET {baseURL}/models` using the configured Bearer token, and let the user select from the returned list.
- Support a non-streaming `POST {baseURL}/chat/completions` request with Bearer authentication.
- Limit the required compatibility surface to `model`, `messages`, and low-variance generation parameters such as `temperature` where supported.
- Store the API key in macOS Keychain.
- Never write the API key to logs or plain-text preferences.
- Allow connection validation from Settings.
- Use separate prompts for Dictate and Translate.
- Show both prompts in Settings, persist user edits locally, and allow each prompt to be restored to its built-in default. The Translate prompt supports the `{{target_language}}` placeholder.
- Treat the recognized transcript as structured, untrusted source text. Questions, commands, role labels, and prompt-like content inside it must be edited or translated, never answered or followed. Keep this source-text boundary separate from the user-editable prompts so it cannot be removed accidentally.
- Use deterministic or low-variance generation settings where supported.
- Require plain-text model output. Markdown wrappers, explanations, and alternative versions must not be inserted into the destination application.
- Keep request construction isolated so endpoint compatibility fixes do not affect product workflow code.

The first version does not need multiple saved API profiles, Responses API support, tool calling, or provider-specific advanced options.

## 11. History

Purrr v1 includes a local history view.

History is stored only on the current Mac. Purrr v1 has no cloud sync. Audio and transcript history are retained for a fixed 24 hours from the session completion time and are then permanently deleted. The retention period is not configurable in v1. Expired records should be cleaned up at application launch and periodically while the application is running.

Every session with captured audio creates a history entry, including failed and dismissed sessions. Each entry stores:

- Completion timestamp.
- Mode: Dictate or Translate.
- Locally stored audio.
- Source transcript.
- Delivered text.
- Target language for Translate entries.
- Status: succeeded, failed, dismissed, or retrying.
- A non-sensitive failure category and user-facing error description when applicable.

The history list should emphasize the delivered text and provide Copy, Retry when applicable, and Delete actions. It also provides Delete All. Copying a successful entry copies the delivered text. If an entry has a source transcript but no delivered text, the copy action copies the source transcript.

Users can delete an individual entry before its automatic expiration. Deletion removes both its audio and transcript data.

### 11.1 Retry

Failed or dismissed entries with retained audio provide a Retry action.

- If speech recognition failed or no final source transcript exists, Retry sends the stored audio through Doubao IME again. A Dictate retry then follows the current language-model toggle, while a Translate retry requires language-model processing to be enabled and configured.
- If speech recognition succeeded but language-model processing failed, Retry may reuse the stored source transcript and rerun only language-model processing. If the language model is currently disabled or incomplete, Purrr prompts the user to configure it first.
- Retry uses the entry's original mode and, for Translate, its original target language.
- Retrying from History must not paste into whichever application currently has focus. It updates the history entry and exposes the result for copying.
- Retry does not extend the entry's original 24-hour retention deadline.

The first version does not require history search, folders, tags, cloud sync, transcript editing, audio playback, or audio download/export. Audio is retained only to support Retry during the 24-hour retention period.

## 12. Text Delivery and Focus Safety

Purrr must capture the destination application when recording starts and validate it again immediately before delivery.

- The floating bar must not steal focus.
- If the original destination remains safe, Purrr pastes the final text into it.
- If focus moved to another application, Purrr must not paste into the new application.
- When automatic delivery is unsafe or fails, Purrr copies the result to the clipboard and shows a clear status.
- Clipboard-based delivery should preserve and restore the previous clipboard value when practical.
- Accessibility permission is required for paste automation.

## 13. Permissions and Onboarding

Purrr must guide the user through granting:

- Microphone permission for audio capture.
- Accessibility permission for automatic paste behavior.

The application should show the current permission state and provide a direct way to request access or open the relevant System Settings pane. For an undetermined microphone state, Purrr must call the system authorization API before opening Settings; merely opening the privacy pane does not register the app in the Microphone list. Permission state should refresh while the Settings window is visible so a change is reflected without reopening Purrr, and newly granted Accessibility permission should re-register the shortcuts automatically.

Development builds should use a stable signing identity when one is available. Repeated ad-hoc signatures can invalidate previously granted TCC permissions because macOS no longer sees the rebuilt bundle as the same trusted app.

## 14. Failure Behavior

- If recording cannot start, keep the destination unchanged and show the error in the bar.
- If Doubao IME fails, do not send audio to another provider automatically.
- If Dictate language-model processing fails after recognition succeeds, deliver the raw transcript automatically and mark the history entry as having used a fallback because cleanup failed.
- If Translate processing fails, do not paste or otherwise present the source transcript as a successful translation. Preserve the source transcript and audio in History so the user can retry or copy the source explicitly.
- Cancellation must stop audio capture, close the speech session, and avoid inserting partial text.
- Empty or silence-only sessions should produce no insertion.
- If the nine-minute limit is reached, Purrr automatically finishes and processes the captured audio rather than discarding it.

## 15. Privacy

Purrr is an internal prototype, but its data flow must still be explicit:

- Audio is sent to the Doubao IME service.
- Recognized text is sent to the user-configured OpenAI-compatible endpoint only when language-model processing is enabled and required for the active flow.
- Purrr must not claim that v1 recognition is local or offline.
- Purrr must not silently change speech or language-model providers.
- Logs must not contain audio, API keys, complete transcripts, or complete translations at normal log levels.
- History is stored locally on the Mac.
- Locally retained audio and transcript data are deleted after 24 hours or when the user deletes the entry.

## 16. Recommended Native Implementation

- SwiftPM-based macOS application.
- Swift and SwiftUI/AppKit for the application shell.
- Menu bar application without a regular Dock icon.
- `AVAudioEngine` for microphone capture.
- Use the current system default microphone. Purrr v1 does not need an input-device selector.
- Native macOS event monitoring for shortcuts.
- A non-activating AppKit panel for the transcription bar.
- macOS Accessibility APIs and clipboard paste fallback for delivery.
- Keychain Services for the language-model API key.
- A small local persistence layer for history.
- Store retained audio as 16 kHz, mono, signed 16-bit PCM WAV. A maximum-duration nine-minute recording is approximately 17 MB before filesystem overhead.
- Use manual `.app` bundle assembly through `Scripts/package_app.sh`.

Begin with a small integration spike that compiles the Koe Doubao IME implementation as a Rust static library behind a narrow C ABI. Reuse it if the FFI boundary, application signing, and bundle packaging remain straightforward. If the spike introduces disproportionate complexity, port only the required Doubao IME protocol implementation to Swift. Do not introduce a Rust-wide provider framework for v1.

Launch at Login is off by default and does not need to be implemented in v1.

## 17. Confirmed Product Decisions

- Dictate and Translate use independent, customizable toggle shortcuts.
- The default shortcuts are `Option-Space` and `Option-Shift-Space`.
- The recording bar displays a waveform rather than interim recognition text.
- Translate initially supports English and Simplified Chinese as target languages.
- Audio, successful transcripts, and failed sessions remain in local history for 24 hours.
- History supports copying and retrying while retained audio remains available.
- Successful delivery shows confirmation for one second before the bar disappears.
- Language-model processing has an explicit on/off toggle.
- With language-model processing off, Dictate returns the raw Doubao IME transcript and Translate directs the user to enable the language model.
- History retention is fixed at 24 hours and History provides Copy, Retry, Delete, and Delete All actions.
- Dictate falls back to the raw transcript when language-model cleanup fails; Translate never pastes an untranslated fallback as a successful result.
- Purrr runs as a menu bar application, uses the system default microphone, and does not implement Launch at Login in v1.
