# Privacy and Data Flow

Purrr performs speech recognition through a remote service and stores history on your Mac.

## Remote Processing

- During Dictate and Translate, microphone audio is streamed to Doubao IME through the unofficial Koe integration. This happens even when LLM processing is disabled.
- The pinned provider uses `frontier-audio-ime-ws.doubao.com` for speech recognition and `log-klink.zijieapi.com` for device registration. Registration sends client/device metadata and returns a cached device identifier. These endpoints are implementation details, not a supported Purrr service contract.
- When LLM processing is enabled, Dictate sends the transcript and editing prompt to the user-configured OpenAI-compatible endpoint. With an empty Dictate prompt, it only requests supported vocabulary spelling corrections; when the template and eligible vocabulary are both empty, it returns raw text without a request. Translate sends the transcript and translation prompt directly to that endpoint; it does not run Dictate polishing first.
- Use vocabulary is one switch for learning and correction. When it and LLM processing are enabled, the full eligible saved-word list accompanies the existing Dictate or Translate request as spelling references. Unaccepted suggestions and unchecked legacy automatic words are excluded. Learning sends bounded before/after snippets from confirmed Dictate edits in a separate semantic-review request. Older unchecked edits are reviewed only after the user selects Check. Turning vocabulary off pauses learning and excludes words from processing without deleting them.
- Vocabulary Instructions and Preview Request are read-only local views. Preview uses an illustrative transcript and current eligible words, displays no credentials, and sends no request.
- Model loading sends an authenticated request to the configured endpoint. Test Connection sends a short synthetic text request. The LLM integration sends text, not recorded audio.
- Purrr does not operate a backend or proxy these requests. The app does not add its own analytics or crash-upload service, but its speech dependency performs the remote device registration described above.

Third-party services may retain audio, transcripts, prompts, vocabulary, edit snippets, identifiers, or request metadata under their own policies. Purrr cannot promise zero retention, control provider-side deletion, or establish that an unofficial endpoint is authorized for a particular use. Do not record confidential, regulated, or otherwise sensitive material with this prototype.

## Local Storage

| Data | Location | Retention |
| --- | --- | --- |
| LLM API key | macOS Keychain, service `io.github.kaiix.purrr`, account `llm-api-key` | Until replaced or removed in Settings |
| Settings and custom prompts | UserDefaults domain `io.github.kaiix.purrr` | Until changed or removed by the user |
| Audio and history index | `~/Library/Application Support/Purrr/History/` | Entries expire 24 hours after session completion |
| Saved words and review metadata | `~/Library/Application Support/Purrr/Vocabulary/vocabulary.json` | Words persist until deleted; review metadata is pruned with its history evidence |
| Doubao device registration cache | `~/Library/Application Support/Purrr/doubaoime_credentials.json` | Reused across sessions; not removed by history cleanup |

History includes successful, failed, and dismissed sessions when data was captured. It can contain source text, final text, audio, and error messages. History and vocabulary are ordinary local files, without app-level encryption. Review metadata contains edit fingerprints, classifications, and approved spellings, not duplicate full snippets. The Keychain protects the LLM API key; it does not encrypt these directories.

Expired history is cleaned up on launch and every 30 minutes while the app is running. Purrr cannot delete files while it is closed. Retry does not reset the original session's retention deadline. Deletion is ordinary filesystem deletion, not secure erasure, and does not remove copies from backups, exported files, the clipboard, or providers.

## Clipboard and Accessibility

Purrr uses Accessibility to intercept its shortcuts, capture the focused typing destination, and simulate paste. It checks that the originating app and focused element still match before inserting text; otherwise it leaves the result on the clipboard for manual paste.

Insertion temporarily writes the result to the system clipboard. After a paste attempt, Purrr restores the previous plain-text clipboard value when one existed and the clipboard has not changed. It does not preserve all clipboard formats or verify that the destination accepted the text. Other applications or clipboard managers may observe clipboard contents. Copying from History intentionally leaves text on the clipboard.

## Deleting Data

Use History's Delete or Delete All actions for retained entries and their audio. Delete saved words separately in Vocabulary; history deletion does not remove them. Clear the API key in Settings to remove its current Keychain item. Uninstalling the app does not automatically remove Application Support files, preferences, Keychain items, or previously granted permissions.

## Safe Configuration and Reporting

Use HTTPS for remote LLM providers. HTTP is supported for local development endpoints but can expose API keys and transcripts if used across an untrusted network. Only configure endpoints you trust, and review the provider's policies before sending data.

Do not attach recordings, history indexes, registration caches, API keys, private prompts, or unredacted provider errors to public issues.
