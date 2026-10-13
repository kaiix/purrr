# Purrr App Surface

## Design Direction

Purrr uses one compact, dependable transcription bar that appears while voice input is active.

Native macOS charcoal and system surfaces carry the product. Grouped controls, system typography, SF Symbols, quiet separators, and semantic accent colors make every state legible. The opaque charcoal control capsule belongs only to the floating transcription bar.

The user presses a shortcut to start recording, presses it again to finish, and receives text in the original app. Settings explain the available options. History provides short-lived recovery and retry.

## Transcription Bar

A fixed 136-by-40-point charcoal capsule sits 12 points above the active screen's usable lower edge. Dictate and Translate use identical outer dimensions. Its circular end caps share a center axis with the 28-point Cancel and Finish controls; continuous-corner smoothing is not used. The actions sit eight points from the capsule edges and frame a 44-point live waveform built from recent microphone levels; the final minute replaces it with a `m:ss` countdown. Processing and result states keep the same outer frame. It never takes keyboard focus or draws an exterior shadow.

Recording, recognition, processing, and delivery lead to a one-second success confirmation. Failures remain visible long enough to read and are retained in History.

## Quality Requirements

Use native macOS controls, compact layouts, and clear state labels. Respect Reduce Motion and preserve the user's typing focus. See `DESIGN.md` for the full design system.

## Vocabulary Direction Contract

**Thesis:** Make word collection visible and reversible, not an invisible correction system. Keep management inside existing Settings rather than introducing a dictionary dashboard.

**Own-world:** Inherit native tabs, compact system typography, semantic colors, inset lists, and standard macOS controls. No new visual identity or custom container style.

**Story:** The user sees that saved words are local and do not affect output yet. Edit snippets are sent to the configured LLM for same-entity correction review. Approved new terms are saved with a notice that offers Undo and opens the word when clicked; older edits require explicit review and manual confirmation. Ordinary rewrites, uncertainty, and failed review never become automatic words.

**First viewport:** A grouped Form matching the other Settings tabs. A collection toggle with a one-sentence explanation precedes a segmented Words / Suggestions control with counts. Words provides a full-width input and Add action, then each saved word with a source glyph; earlier auto-added words that predate checking are marked Not checked. Suggestions shows the explicit Check action with the count of older unchecked edits while any exist, then LLM-approved editable spellings with Add and Dismiss actions and expandable before/after context. If the LLM is unavailable, the toggle states that collection is paused; manual words remain available.

**Form:** A narrow native Settings extension, pinned to the incumbent design. No concept seed or separate composition round applies.

**Finish:** unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance. This extension preserves the existing design system and adds no shipping raster assets.

## Vocabulary Notice

A separate 380-by-44-point capsule reuses the transcription strip's charcoal treatment and lower-edge placement only after editing ends. It carries one line naming the added word and an Undo action. The panel has no exterior shadow, cannot become key or main, and never activates the app on appearance. It is hidden while recording or processing is active, lasts seven seconds, and pauses dismissal while hovered. A batch of new words uses one notice rather than a series of popups. Clicking the line is the explicit focus-changing action: it opens Settings directly at the first added word's editable row. Long terms truncate in the middle and remain complete in the Settings editor.
