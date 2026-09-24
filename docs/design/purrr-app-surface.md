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
