# Doubao IME Parameter Replay Experiments

Date: 2026-10-12 (Asia/Singapore)

Status: Completed diagnostic experiment. Production settings are unchanged.

## Findings

None of the tested configurations reliably produced lowercase ordinary English terms. The mixed-language recording still contained title-cased `Pronoun Gender` or `Pronouns Gender` in all 35 replays of that recording, including the initial smoke run. Disabling recognition passes also weakened formatting and recognition in other recordings.

Relevant context helped recover term spelling: `AllDay` became `Auday` in three runs using a hint containing lowercase `auday`. The spelling improved, but the lowercase preference was not preserved. Context also corrected `promotes` to `prompts` in an English recording. These observations support further work on relevant term hints; they do not establish context as a reliable style instruction channel.

`strong_ddc=true` removed some conversational words in one recording, consistently across two isolated runs, but did not remove repeated audible fillers in another. It cannot replace Purrr's optional LLM polishing.

## Method

- Replayed four existing Purrr WAV recordings containing mixed Chinese/English terminology, an incorrectly recognized app name, English self-corrections, and repeated Chinese fillers.
- Completed 62 sequential sessions: 35 mixed-language, 12 app-name, 11 English, and 4 filler sessions. All received `SessionFinished` without errors.
- Covered 27 configurations, including isolated changes, selected interactions, a combination of Douvo's session/end-frame settings, and repeated controls. This was not a full factorial experiment.
- Used exactly the same WAV bytes within each fixture. Result files contain audio SHA-256 digests.
- Sent 16 kHz mono signed 16-bit PCM through the existing Koe Opus encoder, paced at one 20 ms frame every 20 ms.
- Used Purrr's existing device registration, endpoint, and authentication. The combined configuration matches the selected Douvo session and end-frame settings, not its entire authentication or transport implementation.
- Used the Koe revision pinned by Purrr: `aedc9747564dc5ec5a0203827edb4d6d67909bc0`.
- Patched a private copy of the provider to override session fields/end-frame metadata and capture raw responses. Production sources and the Cargo dependency checkout were not edited.
- Collected responses until `SessionFinished`, rather than stopping at the first provider `Final`. The maximum post-input wait was 12 seconds; none of the sessions reached that timeout.
- Did not invoke a BYOK LLM, paste replayed text, update application history, or upload personal-lexicon entries.

The mixed-language baseline was replayed six times including the smoke run. Five returned `ChatData`; one returned `chat data`. All returned `Pronoun Gender`. This baseline variation prevents assigning an isolated spelling/case change to a parameter without further evidence.

No manually checked full transcription reference was constructed, so these experiments do not report word-error rates or overall accuracy rankings. Quality observations refer to specific returned terms, punctuation, and repetitions.

## Parameter Results

| Parameter or configuration | Experiment | Observed behavior |
| --- | --- | --- |
| `enable_asr_twopass` | Set to `false` in three fixtures | Removed final punctuation. The app-name fixture regained an initial filler. The English fixture returned `we re`, an audible `uh`, and `V七` rather than `V7`. Did not remove title case reliably. |
| `enable_asr_threepass` | Set to `false` in three fixtures, with a mixed-language repeat | Mixed-language results used `chat data` but retained `Pronoun Gender`/`Pronouns Gender` and introduced plural variation. The English fixture returned `we 7`; another fixture returned lowercase `codex`. Casing changes came with recognition changes. |
| Both recognition passes | Set both to `false` in three fixtures | Still returned `ChatData` in the mixed-language fixture, with no punctuation. Did not provide a reliable raw/lowercase mode. The switches are not independent guarantees of specific processing stages. |
| `enable_text_post_process` | Compared omitted, `true`, and `false`; repeated `false` and tested English | `true` matched the mixed-language baseline. `false` retained title case/CamelCase, removed punctuation, and returned a settled snapshot with `is_interim=false`, `is_vad_finished=false`. Koe classified it as `Definite`, not `Final`; the probe still captured it before `SessionFinished`. The English result also contained recognition regressions. |
| `asr_text_post_process_type` | Sent `last_post_process` alone, with processing enabled/disabled, and with selected pass changes | No additional effect distinguishable from the companion switches. Enabling processing plus `last_post_process` did not fix mixed-language casing. No differing later revision was observed after the first provider `Final`. Other enum values were not guessed or tested. |
| `enable_punctuation` | Set to `false`, repeated on mixed-language audio and tested English | Final text still contained punctuation with the default passes enabled. This field alone did not disable punctuation in these samples; that does not prove the server universally ignores it. |
| `strong_ddc` | Compared omitted, `true`, and `false` across relevant fixtures | On the app-name fixture, `true` removed conversational equivalents of "that" and "then" in two isolated runs. The same reduction appeared in the combined configuration. In the filler fixture, all four configurations retained repeated fillers and repeated wording. It did not correct `AllDay` or guarantee case preferences. |
| `use_twopass_retry` | Compared omitted, `true`, and `false` | No distinguishable effect during normally successful sessions. This does not test retry behavior after a recognition failure. |
| `enable_print_chinese` | Compared omitted, `true`, and `false` | No text/language difference in the mixed-language fixture. Its operational meaning remains unverified. |
| `disable_user_words` | Compared omitted, `true`, and `false` | No effect separable from baseline variation. No test words were uploaded and no known matching personal-lexicon entry was available, so recognition benefits from a populated lexicon remain untested. |
| `context` | Sent Douvo-shaped Base64 JSON with a short, constructed relevant hint; repeated the app-name experiment | Recovered `Auday` from `AllDay` in three context-bearing sessions, including the combined configuration. Did not retain lowercase `auday`. Corrected `promotes` to `prompts` in two context-bearing English sessions. The mixed-language title-cased phrase persisted. |
| Client metadata in `extra` | Added Douvo's `app_version`, `aid`, `version_code`, `version_name`, and `update_version_code` | No distinguishable effect when added alone. Values were taken from Douvo's current source (`1.1.2`, `100102018`, `401734`); Purrr's user-agent/authentication remained fixed. |
| `finish_audio` | Added `true` only to the last audio frame | No distinguishable mixed-language text or finalization difference. |
| `force_asr_twopass` | Added `true` only to the last audio frame | No distinguishable mixed-language text or finalization difference. |
| Both end-frame fields | Added both as `true` | No distinguishable mixed-language result difference. The baseline also finished successfully. |
| Douvo session/end-frame combination | Added explicit post-processing, strong DDC, retry, metadata, lexicon-off, and final-frame fields | Did not fix title case. Removed the same conversational words as strong DDC in the app-name fixture; had no effect on repeated fillers in the filler fixture. Adding context recovered term spelling, but one English output still contained repeated wording. |

All configurations were accepted sufficiently to start, return recognition text, and finish the session. Acceptance alone does not prove every submitted field was recognized by the server. A parameter with no observed difference must not be described as universally ineffective.

## Implications for Purrr

1. Keep the existing recognition passes while investigating writing style separately. Disabling them is not a reliable casing fix and caused concrete formatting/recognition regressions.
2. Keep `rawTranscript` faithful to the speech engine. Any future casing normalization belongs to a separately identifiable processed stage.
3. Treat casing style as a concise general preference. Keep actual term corrections such as `AllDay -> auday` in a dictionary, and select relevant terms rather than placing every past edit in a prompt.
4. Consider relevant ASR context as a term-disambiguation experiment. The observed spelling improvements are promising, but the samples are too small to justify unrestricted conversation-context capture or a production rollout.
5. Treat strong DDC as partial cleanup, with explicit quality evaluation before changing defaults. It can delete conversational words while leaving more obvious fillers and repetitions untouched.
6. Do not assume `last_post_process` always produces a later revised snapshot. None of these sessions did. Any future adapter changes should still retain the latest settled text and distinguish response flags from session completion.

## Local Artifacts and Reproduction

Private diagnostic artifacts are in the Git-ignored directory:

```text
build/asr-probe.eKqzFd/
  Cargo.toml
  src/main.rs
  src/doubaoime.rs
  run_matrix.py
  summary.json
  results/*.variant.json
  results/*.trace.jsonl
  results/*.result.json
  results/smoke.json
```

The summary contains 61 matrix runs; the separate initial smoke result makes the total 62. Raw audio is referenced in Purrr's History directory and was not copied into the repository. It remains subject to History's existing 24-hour expiration.

While those recordings still exist, the diagnostic binary can replay a selected configuration:

```bash
python3 build/asr-probe.eKqzFd/run_matrix.py selected \
  --fixture mixed --variants baseline,threepass_off --suffix=--new-repeat
python3 build/asr-probe.eKqzFd/run_matrix.py analyze
```

The fixture names map to existing local recording IDs in the private runner. New repetitions require a new suffix because the runner preserves completed results rather than overwriting them. Credentials are referenced at their existing path; their values and the session device ID are not written into the experiment report or request-configuration traces.

Source references:

- [Pinned Koe IME implementation](https://github.com/missuo/koe/blob/aedc9747564dc5ec5a0203827edb4d6d67909bc0/koe-asr/src/doubaoime.rs)
- [Douvo session, end-frame, and result implementation](https://github.com/rhinoc/douvo/blob/main/Sources/Douvo/DoubaoAndroidASRClient.swift)
- [Douvo context envelope](https://github.com/rhinoc/douvo/blob/main/Sources/Douvo/AndroidASRContext.swift)
- [Douvo client metadata](https://github.com/rhinoc/douvo/blob/main/Sources/Douvo/DoubaoAndroidCredentialStore.swift)
