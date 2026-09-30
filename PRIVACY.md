# Privacy and Data Flow

Purrr is a personal-use prototype. Local history does not mean local speech recognition.

## Remote Processing

- During Dictate and Translate, microphone audio is streamed to Doubao IME through the unofficial Koe integration. This happens even when LLM processing is disabled.
- The pinned provider uses `frontier-audio-ime-ws.doubao.com` for speech recognition and `log-klink.zijieapi.com` for device registration. Registration sends client/device metadata and returns a cached device identifier. These endpoints are implementation details, not a supported Purrr service contract.
- When LLM processing is enabled, Dictate can send the transcript and editing prompt to the user-configured OpenAI-compatible endpoint. An empty Dictate prompt bypasses LLM processing. Translate sends the transcript and translation prompt directly to that endpoint; it does not run Dictate polishing first.
- Model loading sends an authenticated request to the configured endpoint. Test Connection sends a short synthetic text request. The LLM integration sends text, not recorded audio.
- Purrr does not operate a backend or proxy these requests. The app does not add its own analytics or crash-upload service, but its speech dependency performs the remote device registration described above.

Third-party services may retain audio, transcripts, prompts, identifiers, or request metadata under their own policies. Purrr cannot promise zero retention, control provider-side deletion, or establish that an unofficial endpoint is authorized for a particular use. Do not record confidential, regulated, or otherwise sensitive material with this prototype.

## Local Storage

| Data | Location | Retention |
| --- | --- | --- |
| LLM API key | macOS Keychain, service `io.github.kaiix.purrr`, account `llm-api-key` | Until replaced or removed in Settings |
| Settings and custom prompts | UserDefaults domain `io.github.kaiix.purrr` | Until changed or removed by the user |
| Audio and history index | `~/Library/Application Support/Purrr/History/` | Entries expire 24 hours after session completion |
| Doubao device registration cache | `~/Library/Application Support/Purrr/doubaoime_credentials.json` | Reused across sessions; not removed by history cleanup |

History includes successful, failed, and dismissed sessions when data was captured. It can contain source text, final text, audio, and error messages. It is stored as ordinary local files, without app-level encryption. The Keychain protects the LLM API key; it does not encrypt the history directory.

Expired history is cleaned up on launch and every 30 minutes while the app is running. Purrr cannot delete files while it is closed. Retry does not reset the original session's retention deadline. Deletion is ordinary filesystem deletion, not secure erasure, and does not remove copies from backups, exported files, the clipboard, or providers.

## Clipboard and Accessibility

Purrr uses Accessibility to intercept its shortcuts, capture the focused typing destination, and simulate paste. It checks that the originating app and focused element still match before inserting text; otherwise it leaves the result on the clipboard for manual paste.

Insertion temporarily writes the result to the system clipboard. After a paste attempt, Purrr restores the previous plain-text clipboard value when one existed and the clipboard has not changed. It does not preserve all clipboard formats or verify that the destination accepted the text. Other applications or clipboard managers may observe clipboard contents. Copying from History intentionally leaves text on the clipboard.

## Deleting Data

Use History's Delete or Delete All actions for retained entries and their audio. Clear the API key in Settings to remove its current Keychain item. Uninstalling the app does not automatically remove Application Support files, preferences, Keychain items, or previously granted permissions. Any data retained under an earlier development bundle identifier must be removed separately.

## Safe Configuration and Reporting

Use HTTPS for remote LLM providers. HTTP is supported for local development endpoints but can expose API keys and transcripts if used across an untrusted network. Only configure endpoints you trust, and review the provider's policies before sending data.

Do not attach recordings, history indexes, registration caches, API keys, private prompts, or unredacted provider errors to public issues.
