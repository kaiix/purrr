# Final Edited Text, Conversation Context, and Dictionary Plan

Status: Accepted implementation plan; generic final-edit tracking and LLM-reviewed collection-only vocabulary implemented

Date: 2026-10-13

## Purpose

Purrr knows what the speech engine recognized and what Purrr inserted. It also needs the last readable value when the user finishes the resulting editing session, whether that session ends through a submit gesture, pointer interaction, focus change, field clearing, or inactivity.

The current increment closes that gap with an application-independent target matcher and edit-end state machine. This evidence can later support bounded conversation context and local dictionary learning. Synchronization with the unofficial Doubao IME personal lexicon remains a later, separately validated step.

This document records the analysis behind that order and the decisions that follow from it. It extends, but does not expand, the initial v1 Dictate and Translate feature set into a general assistant.

## Decision Summary

1. History will preserve three distinct text stages: raw transcript, processed text, and final edited text.
2. Purrr will observe editing only for a short period after it inserts text. It will not continuously monitor unrelated typing.
3. The tracked value represents the end of the editing session, not proof that a third-party application completed a network submission.
4. Dictate and Translate keep separate processing prompts, but their contextual history is not separated by mode. Context belongs to a verified conversation, not to a feature mode.
5. Accessibility identifiers are useful evidence but are not conversation identifiers. Purrr will fail closed when it cannot verify conversation continuity.
6. Historical text is optional, weak context. It may help with terminology and continuity, but it must never be treated as a complete conversation or as model instructions.
7. The local dictionary is the source of truth. Doubao IME synchronization is optional and must not block dictation.
8. Speech-lexicon learning and translation-glossary learning are different problems. Translate corrections must not automatically become Doubao speech-recognition terms.

## Terminology

- **Raw transcript**: the final text returned by the speech engine.
- **Processed text**: the exact text Purrr produced after optional LLM cleanup or translation and attempted to insert.
- **Final edited text**: the last readable non-empty value related to Purrr's insertion when the editing session ends.
- **Edit-end candidate**: an interaction or state transition that may end editing, including Return, pointer interaction, clearing, focus change, or inactivity.
- **Conversation continuity**: high-confidence evidence that two submissions belong to the same destination conversation or document context.

The persisted Swift fields retain their existing `submittedText` and `submission*` names for storage compatibility, but their product meaning is final edited text and edit-end evidence. Delivery alone does not create this stage.

## Why Final-Edit Capture Comes First

Final edited text is the strongest available feedback signal:

- `rawTranscript -> processedText` measures speech recognition plus LLM behavior.
- `processedText -> final edited text` isolates the user's corrections to Purrr's output.
- Repeated localized corrections can produce dictionary candidates.
- Final edits provide correction evidence. Reusing them as conversation context additionally requires evidence that the text entered the destination conversation.

Building dictionary learning before this signal exists would train it on Purrr's own output rather than on the user's accepted wording. Conversation context has a separate, stronger continuity and delivery requirement because an editing session can end without submission.

## Bounded Post-Insertion Observation

### Observation window

Purrr starts a temporary observation session only after successful insertion. The session is associated with one history entry and contains, in memory:

- Destination process identifier and bundle identifier.
- A semantic target descriptor composed from application, window, document, control, capability, ancestor, identifier, and geometry evidence when exposed.
- The focused element reference while it remains valid.
- Field value and selection before insertion.
- The inserted processed text and its expected range.
- Field value and selection immediately after insertion.
- The latest non-empty value observed in the destination field.
- A 15-second inactivity deadline, refreshed by relevant keyboard or pointer activity.

Target matching produces a confidence-based relationship rather than relying on `AXUIElement` identity or a single identifier. Web views often replace the native accessibility wrapper for the same logical composer after an edit or render pass. Control identity and destination-context identity are evaluated separately.

The observer combines three signals:

- A global event tap captures relevant keys and left-button interactions before the destination application handles them.
- Accessibility value and focus notifications request immediate refreshes when the destination supports them.
- A one-second poll provides a fallback for applications or web views that omit those notifications.

The pre-insertion and post-insertion field snapshots are transient. They must not be added to history, logs, analytics, or model requests.

Observation ends when any of the following occurs:

- A confirmed edit-end transition occurs.
- The field remains cleared after a short debounce.
- Focus moves to another control, window, or application.
- Fifteen seconds pass without relevant editing activity.
- The observation becomes unreadable and no final value can be established.

### Edit-end evidence

A key press or pointer interaction is a candidate action, not proof of submission. For example, `Return` sends a ChatGPT message but inserts a newline in a document editor. Purrr records the end of editing rather than claiming that the destination completed submission.

Purrr captures the current field value immediately before a candidate interaction and then observes the result after the destination application handles it. The latest related non-empty snapshot is retained so a cleared or replaced composer cannot erase the value Purrr is trying to record.

Confirmation rules are intentionally control-aware:

- `Return` in a single-line text field confirms immediately. This covers controls such as browser address fields.
- `Command-Return` confirms immediately because it is an explicit submission gesture in supported workflows.
- `Return` in a multiline field remains pending until the field clears, is replaced, or loses focus.
- If the same multiline field instead gains a newline or otherwise changes in place, the candidate is cancelled.
- `Shift-Return`, modified Return variants other than `Command-Return`, and repeated key events are not submission candidates.
- A left-button interaction captures the pre-click value and is confirmed only if editing subsequently ends.
- Clearing and focus changes are debounced so transient accessibility updates do not finish the session immediately.
- Inactivity records a final value only when Purrr previously observed a readable value related to its insertion.

The appearance of the final text in nearby accessible content remains a possible future confidence signal, but it is not required for this generic phase.

The generic implementation does not inspect button labels or application identities. Pointer-driven send buttons are covered through before/after field transitions rather than application-specific knowledge.

### Confidence and failure behavior

Use the following persisted states:

- `notObserved`: no post-insertion observation was started, including History retry results that are not pasted.
- `pending`: observation is active; this state is normally transient.
- `confirmed`: the observer captured a readable final edited value and edit-end evidence.
- `unknown`: observation ended without sufficient evidence.
- `cancelled`: the user removed or dismissed the inserted content before submission.

Only `confirmed` records may provide final edited text to context or dictionary learning. An inaccessible destination without a previously observed related value results in `unknown`; Purrr does not substitute processed text for focus loss or inactivity.

This deliberately misses some real submissions. A false negative loses optional context; a false positive can mix private text from unrelated destinations and is therefore more harmful.

## History Model Version 2

The persisted entry should evolve toward the following conceptual model:

```swift
struct HistoryEntry {
    let id: UUID
    let completedAt: Date
    var mode: SessionMode
    var rawTranscript: String?
    var processedText: String?
    var submittedText: String?
    var submissionState: SubmissionState
    var submittedAt: Date?
    var submissionEvidence: SubmissionEvidence?
    var targetLanguage: TranslationLanguage?
    var destination: DestinationFingerprint?
    var contextEvidence: ContextEvidence?
    // Existing audio, status, retry, fallback, and failure fields remain.
}
```

The exact Swift types may remain smaller in the first migration. Persist only stable, non-sensitive destination metadata; do not persist complete surrounding field or window contents.

Existing entries migrate as follows:

- `sourceText` becomes `rawTranscript`.
- `deliveredText` becomes `processedText`.
- `submittedText` remains absent and `submissionState` becomes `notObserved`.

### History presentation

Each entry is collapsed to the latest available text and copies it when clicked. Expanded, it always lists three stages:

1. Final
2. Polished (Translated for Translate sessions)
3. Transcript

Polished or Translated is the user-facing label for the persisted `processedText` value. Each stage with distinct text displays it completely and copies it when clicked. An unavailable final stage displays a neutral value such as "Not captured" rather than silently reusing processed text, and an identical stage is identified as unchanged ("Same as transcript", "Same as polished") rather than repeated or omitted. An expanded comparison may highlight both `Transcript -> Processed` and `Processed -> Final` edits.

Retry updates the raw and processed stages but sets the submitted stage to `notObserved`, because a History retry is not pasted automatically.

The existing 24-hour retention and deletion behavior applies to every text stage and its destination metadata.

## Conversation Context

### Dictate and Translate are not separate conversations

Processing remains mode-specific:

- Dictate uses the Dictate prompt and produces polished source-language text.
- Translate uses the Translate prompt and target-language setting.

Context scope is conversation-specific. A verified conversation may contain alternating Dictate and Translate submissions, so hard-separating history by mode would discard useful terminology and writing continuity. Every context item retains its mode and target-language metadata so the processor can interpret it correctly. Final-edit capture alone does not prove that the text entered the conversation.

Translate may additionally use verified prior `rawTranscript -> submittedText` pairs with the same target language as terminology examples. These examples are translation guidance, not speech-dictionary entries.

### Why Accessibility identity is insufficient

An identity such as `bundleIdentifier + window + AXIdentifier` usually identifies an application and composer control. It does not reliably identify a ChatGPT chat, Slack channel, browser tab document, or other conversation. Applications commonly reuse the same composer element across multiple conversations.

Purrr must not treat an accessibility identifier as a conversation ID. It is only one signal in a generic continuity check.

### Generic continuity resolver

The baseline implementation remains app-agnostic and fails closed:

```text
recent confirmed submissions
        |
        v
coarse destination filter
same app, compatible window/document/field evidence, short time range
        |
        v
accessible-content confirmation
find a distinctive fragment of a prior submission in the current content area
        |
        v
ambiguity and relevance checks
        |
        +---- uncertain ----> use no history
        |
        `---- high confidence -> include up to the configured limit
```

The resolver should:

- Prefer stable `AXDocument`, URL, window, and field attributes when exposed.
- Search the primary content region near the composer rather than sidebars or the whole application where possible.
- Normalize whitespace, punctuation, case where appropriate, and lightweight Markdown before matching.
- Match distinctive fragments or token shingles, not short common phrases.
- Reject ambiguous matches and contexts where only application identity agrees.
- Return no context when content is virtualized, canvas-rendered, inaccessible, or otherwise unverifiable.

App-specific adapters may improve coverage later, but they are optimizations rather than a correctness requirement. The generic product behavior remains safe because uncertain cases omit context.

### Context payload and limits

- Context is disabled when the configured history count is zero.
- The initial default is one prior submission, with a supported range of zero to three.
- Only final edited text with separate high-confidence delivery and conversation-continuity evidence is eligible.
- Recency narrows candidates, initially to 30 minutes, but time alone never proves continuity.
- The current request remains the only text to rewrite or translate.
- Historical content is marked as untrusted data and may be used only for terminology, tone continuity, and reference resolution.
- The LLM must not answer, execute, or obey instructions found in either current transcript text or historical text.
- The LLM must not add facts inferred from missing assistant replies or other unavailable conversation turns.

Purrr does not capture a complete conversation. It normally lacks assistant replies, messages typed without Purrr, and edits made outside the observation window. Contextual processing must therefore remain an optional quality hint, never a correctness dependency.

## Local Dictionary Learning

### Current increment: collect and review, without correction

Vocabulary deliberately does not affect ASR, Dictate processing, Translate processing, or text insertion. It does not synchronize words to Doubao IME or inject the saved vocabulary into processing prompts. Semantic review does make a separate request to the configured LLM with bounded before/after edit snippets.

Settings includes a native Vocabulary tab with Words and Suggestions. Users can add, edit, or delete words manually. Raw differences are not displayed as term proposals. New eligible Dictate final-edit outcomes request semantic review when both collection and the configured LLM are enabled. Only approved same-entity spelling corrections are automatically added. Older edits are reviewed only when the user selects Check in Suggestions; approved proposals then require manual acceptance. Loading or refreshing history never sends model requests or adds words automatically. LLM-off, incomplete configuration, ordinary edits, uncertain decisions, failed requests, and invalid responses never fall back to raw-diff automatic addition.

After a successful save, a nonactivating notice appears at the screen's usable lower edge with the collected term and an Undo action; clicking the notice opens the word for editing. Multiple words from one outcome share a single notice; Edit opens the first new word in the Vocabulary tab, scrolls to its row, and focuses its spelling field. Undo atomically removes only the notice's new words and refuses if any was subsequently edited or removed. Dismissed edit fingerprints prevent the same captured edit from immediately adding an undone word again; they do not blacklist that spelling for every future session. Close or timeout keeps the words. The notice lasts seven seconds, pauses while hovered, and waits while the transcription bar is active. It never claims that an unsaved word was added.

Saved words persist separately from the 24-hour history in the app's local application-support directory. Their minimal model is `id`, `term`, `source` (`manual`, `confirmedEdit`, or `autoAdded`), `createdAt`, and an optional `reviewedByLLM` flag. Older auto-added words lacking that flag remain intact and are labeled as predating semantic review; they are not silently deleted or automatically re-uploaded for review. Case and diacritics are preserved; duplicate checks ignore case and repeated whitespace but do not strip diacritics. Observed misspellings are not replacement rules and are not stored in saved words.

Candidate evidence is derived from unexpired history rather than copied into a second durable transcript store. Deleting or expiring a history entry removes its review candidates when the history updates. Dismissal metadata contains an entry identifier and an edit fingerprint, not plaintext before/after phrases. Saved words survive history deletion until the user removes them explicitly.

### Local comparison algorithm

1. Use only successful Dictate entries with confirmed Final text and an available Polished stage. Compare `processedText -> submittedText`, not raw ASR text against Final: the former isolates user edits rather than learning the LLM's own changes.
2. Normalize Unicode to NFC and tokenize both texts with macOS `NLTokenizer` at word granularity. Token equality ignores case. Keep original string ranges for exact spelling and context display.
3. Use Swift's standard `CollectionDifference` sequence comparison to locate unchanged anchors and contiguous changed spans. Consider only small replacement hunks with both an original and a corrected side. This supports `AllDay`, `all day`, or `aw day` being edited to `auday`, without requiring a previously known alias.
4. Exclude pure insertion/deletion, punctuation/case/spacing-only changes, numeric or identifier-like fragments, and long replacement spans. Bound inputs to 16,000 characters and 512 word tokens per side; limit each replacement to four tokens and each suggested term to 60 characters. Broad rewrites are excluded when at least 12 tokens are involved and more than half the combined token count is changed.
5. Submit local candidates for semantic review. After approval, store complete corrected terms from new live outcomes and show the reversible notice. Older history remains a manually triggered review queue. Automatic addition stores only spelling guidance, not a forced replacement rule.

Local filters alone do not classify semantics. A small ordinary rewrite may pass them, but cannot reach automatic collection without LLM approval. Real corrections may still be missed because of tokenization, repeated words, existing composer content, or length limits. Chinese word boundaries and one-character changes are not always recoverable as a complete name. Users can undo a mistaken addition, edit the spelling, or add the complete term manually. The captured Final is an editing-end snapshot, not proof of message delivery or a perfect insertion-only span. The model can also misclassify; approval is not a guarantee of correctness.

### Implemented semantic review

Diff answers *what changed*, not *why it changed*. Purrr now reuses the existing OpenAI-compatible endpoint, API key, and selected model for a distinct classification task. It does not use the user's Dictate or Translate prompt. The request marks every edit string as untrusted data and asks for `term_correction`, `ordinary_edit`, or `uncertain`, plus the complete corrected term only for accepted corrections.

Entity detection alone is insufficient: replacing ChatGPT with Claude changes the entity rather than correcting its spelling. Learn only names, products, projects, or specialized fixed terminology where the before/after context indicates the same referent. Do not learn general rephrasing, grammar, fillers, everyday words, capitalization preferences, numbers, dates, paths, credentials, or arbitrary code identifiers. The reported 应该 -> 定义 and 然后 -> 和官方回复 edits are explicit examples of non-terminology changes.

Requests contain at most 12 edits. Each snippet preserves up to six neighboring word tokens per side, capped at 200 characters before and after the changed span. Provider payloads use temporary numeric edit IDs, not history UUIDs or destination metadata, and contain no audio or complete history. Excess candidates remain available for subsequent manual review; opening Settings alone never submits them.

The client validates JSON shape, complete and unique decision IDs, allowed actions, term length, control characters, and exact term presence in the corrected context. An accepted term must also overlap the changed fragment, preventing an unrelated nearby entity from being learned. No canonical case or spelling absent from the user's Final is invented. Results are rejected when their corresponding edit has been removed, expired, retried, changed, or collection has been disabled while the request was in flight. Model processing does not block recording or text delivery.

Successful semantic decisions persist in the local vocabulary snapshot, keyed by each edit fingerprint. Store the action and, for an approved correction, its exact spelling; do not duplicate complete before/after snippets. Ordinary and uncertain outcomes count as checked, and approved but unaccepted suggestions recover after restart without another LLM request. Tracking each edit independently rather than using a time or row cursor preserves unchecked edits when batches finish out of order and treats revised edits as new evidence. Switching collection off hides suggestions without clearing completed reviews.

Every successful batch is saved atomically even when it adds no words. Invalid responses, failed requests, or failed saves never mark an edit as checked. Deleting, expiring, or replacing the corresponding history evidence prunes its review metadata on refresh; saved words remain until explicitly deleted. Stored approved spellings are revalidated against current candidate evidence. Older vocabulary files without review results still load normally, but prior in-memory decisions cannot be recovered: older unchecked edits need one successful check after this update. Previously auto-added words remain visible with provenance and can be removed manually.

Verification on 2026-10-13: 37 automated tests passed, including synthetic OpenAI-compatible request inspection, response validation, exclusion of ordinary and uncertain decisions, stale-evidence checks, legacy storage, and retryability after a failed save. Persistence regressions exercise reloads after mixed decisions, unaccepted suggestions, manual-review save failure, disabled collection, out-of-order batches, changed edits, deletion, and expiry. An earlier isolated native preview verified the pending-review screen and the transition from two synthetic edits to one approved term. These checks use supplied model responses, not real inference; accuracy of the configured model still needs observation during actual use. No production history, credentials, audio, or live provider requests were used for verification.

### Future use of confirmed vocabulary

When correction is enabled in a later increment, a small vocabulary should be provided to the LLM as a complete list of enabled canonical terms. Do not gate participation on an exact match against current ASR text or known misspellings: pronunciation and recognition output vary across sessions. Vocabulary is spelling guidance, not a command to replace every similar ordinary phrase. For example, `auday` must not force “I worked all day” into a product-name reference. Explicit deterministic replacement rules, if added, are a separate opt-in capability. A large vocabulary may later need a bounded, high-recall selection strategy; a retrieval framework is not needed for the collection-only increment.

Doubao context belongs before recognition and remains a separate future experiment. It is not a final correction stage after LLM processing.

### External evidence and its limits

- [Typeless's official guide](https://www.typeless.com/help/quickstart/history-and-dictionary) confirms automatic learning of preferred spelling after a user correction and manual entry of correct words or phrases. It does not disclose the diff algorithm, semantic classifier, whether an LLM is used for learning, or whether the entire vocabulary is supplied at runtime. Snapshot comparison followed by semantic term selection is a plausible design, not a verified description of Typeless internals.
- VoiceInk provides a verifiable open-source example: its [CorrectionDiffEngine](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Dictionary/AutoLearn/CorrectionDiffEngine.swift) extracts localized edit evidence, and its [AutoLearnAIReviewer](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Dictionary/AutoLearn/AutoLearnAIReviewer.swift) submits before/after snippets for structured AI review. Purrr likewise separates local differences, semantic review, and reversible collection. This is an architectural reference, not copied code.

The remaining sections describe the longer-term learning design, not behavior enabled in the collection-only increment.

### Candidate generation

Dictionary candidates come from localized differences between processed text and confirmed submitted text. A candidate is stronger when:

- The edit is a small replacement rather than a large rewrite.
- The replacement resembles a name, product, acronym, or domain-specific term.
- The observed and corrected forms are phonetically or orthographically similar.
- The same correction appears more than once.
- The correction is not only punctuation, spacing, capitalization without semantic value, or general rewriting.

Example:

```text
Raw transcript:  Do you know TypeList?
Processed text:  Do you know TypeList?
Submitted text:  Do you know typeless?
Candidate:        TypeList -> typeless
```

The current collection-only increment adds only LLM-approved corrections from new outcomes, with Undo and click-to-edit. It does not use a model-reported numeric confidence threshold or apply corrections to output. Ordinary and uncertain decisions are excluded from both automatic collection and the approved-proposal list.

### Mode-specific learning

- Dictate corrections may create speech-lexicon candidates because processed and submitted text normally represent the same language and intent.
- Translate corrections normally create translation-glossary candidates for a source/target pair. They must not automatically update the Doubao speech lexicon because the submitted text can be in a different language from the recognized speech.
- Same-language Translate may become eligible only when language identity and the localized correction are both high confidence.

### Local source of truth

The local model should support at least:

```text
canonicalTerm
observedForms[]
kind: speechLexicon | translationGlossary
source: manual | learned
confidence
occurrenceCount
enabled
createdAt
updatedAt
```

Local entries can immediately guide LLM processing. Remote synchronization is an independent capability and cannot determine whether a local entry exists.

## Doubao IME Personal Lexicon

Current evidence comes from unofficial clients and private Doubao IME endpoints, not from a supported public API. The observed protocol appears to provide term upload and a whole-lexicon enable/disable flag associated with an anonymous device identifier. The remote state appears persistent and device-scoped rather than tied to a normal user account.

The following capabilities are not yet verified:

- Listing or reading remote terms.
- Updating or renaming one term.
- Deleting one term.
- Clearing the entire remote lexicon.
- Word length, character set, count, batch, language, and rate limits.
- Duplicate and idempotency behavior.
- Whether remote entries survive device re-registration indefinitely.

Before synchronization is enabled, test with an isolated device identifier and unique disposable terms:

1. Add one term and verify recognition in a new ASR session.
2. Add another term incrementally and verify that the first remains effective.
3. Repeat an identical upload and observe duplicate behavior.
4. Relaunch and re-register to determine persistence boundaries.
5. Observe edit, delete, clear, and disable operations in an official client if available.
6. Probe limits conservatively without uploading real personal vocabulary.

Until per-term deletion behavior is confirmed, Purrr must not automatically upload learned terms. A future synchronization design should use a per-device incremental queue, retry independently of dictation, expose an experimental opt-in, and explain that changing the anonymous device identifier may require re-uploading active local terms while leaving old remote state behind.

## Implementation Order

### Phase 1: History model

- Add raw, processed, and submitted stages plus submission state.
- Migrate existing `sourceText` and `deliveredText` records without data loss.
- Keep 24-hour retention and retry semantics unchanged.

### Phase 2: Final-edit observation

- Start a bounded observer after successful insertion.
- Match editing targets using a confidence-weighted semantic descriptor.
- Observe keyboard, pointer, clearing, focus, and inactivity signals without application-specific rules.
- Preserve the last readable value associated with Purrr's insertion.
- Stop cleanly on edit end or an unreadable accessibility state.

### Phase 3: History comparison UI

- Display complete Final, Polished, and Transcript text for every entry.
- Provide an independent copy action for each available stage.
- Make unavailable states explicit.
- Add compact comparisons without turning History into an editor.

Implementation note: phases 1 through 3 now use a generic edit-end state machine. Pointer-driven buttons are covered by observing the input transition; Purrr does not inspect application identities or button labels. Automatic interaction-profile learning remains a later phase.

### Future phase: interaction-profile learning

- Learn gesture and transition patterns only from high-confidence local observations.
- Scope learned behavior by semantic control and context features rather than handwritten application adapters.
- Keep uncertain outcomes out of the learning set and retain an explainable evidence trail.
- Store structural statistics locally without retaining additional field contents.

### Phase 4: Generic context continuity

- Implement the fail-closed resolver.
- Add a zero-to-three context limit with a default of one.
- Harden the LLM request boundary for untrusted history.
- Verify that switching conversations in the same application omits context unless continuity can be proven.

### Phase 5: Local learning

- Generate correction candidates from confirmed submissions.
- Add local dictionary and translation-glossary storage.
- Apply local terms to LLM processing and provide confirmation or Undo where required.

### Phase 6: Remote lexicon research and synchronization

- Complete the Doubao IME capability matrix.
- Add optional incremental synchronization only after deletion and privacy behavior are understood.

## Acceptance Scenarios

- A user dictates "TypeList," edits it to "typeless," and submits it. History shows all three stages, and the localized correction becomes a dictionary candidate.
- A later dictation in the same verifiable conversation can receive the confirmed "typeless" submission as context.
- Switching to another ChatGPT chat in the same app does not reuse the first chat's history unless accessible-content evidence proves continuity.
- Pressing `Return` in a document editor inserts a newline and does not create a confirmed submitted stage.
- A timeout or inaccessible destination records "Not observed" and contributes no context or dictionary term.
- A corrected translation can improve the translation glossary but does not silently alter the Doubao speech lexicon.
- Disabling or failing remote lexicon synchronization does not affect Dictate or Translate availability.

## Explicit Non-Goals for This Plan

- Global keystroke logging or continuous field-content capture.
- Reconstructing complete third-party conversations.
- Treating application, window, or accessibility identifiers as guaranteed conversation IDs.
- App-specific ChatGPT, Slack, browser, or editor integrations in the baseline implementation.
- Automatically uploading learned vocabulary before remote deletion semantics are known.
- Using historical content to answer questions or act as an assistant.

## Evidence Reviewed

- Typeless history and dictionary behavior: <https://www.typeless.com/help/quickstart/history-and-dictionary>
- Koe Doubao IME implementation: <https://github.com/missuo/koe/blob/main/koe-asr/src/doubaoime.rs>
- Douvo ASR provider notes: <https://github.com/rhinoc/douvo/blob/main/docs/asr-providers.md>
- Douvo personal lexicon implementation: <https://github.com/rhinoc/douvo/blob/main/Sources/Douvo/DoubaoAndroidPersonalLexicon.swift>

These references are implementation evidence, not stable service contracts. Purrr must isolate private Doubao behavior behind replaceable boundaries.
