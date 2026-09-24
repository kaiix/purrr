---
name: Purrr
description: A quiet native macOS transcription utility built around immediate proof of life.
colors:
  accent: "AccentColor"
  brand-mark: "#1687ff"
  surface: "Canvas"
  text-primary: "CanvasText"
  text-secondary: "GrayText"
  separator: "color-mix(in srgb, CanvasText 10%, transparent)"
  status-success: "light-dark(#34c759, #30d158)"
  status-warning: "light-dark(#ff8d28, #ff9230)"
  status-error: "light-dark(#ff383c, #ff4245)"
  on-status: "#ffffff"
typography:
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 700
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  status-primary:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 600
  status-secondary:
    fontFamily: "ui-rounded, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "11px"
    fontWeight: 500
  shortcut:
    fontFamily: "ui-rounded, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "13px"
    fontWeight: 500
rounded:
  strip: "999px"
  circular: "999px"
spacing:
  micro: "3px"
  compact: "8px"
  inline: "14px"
  control: "18px"
  section: "20px"
  window: "24px"
components:
  transcription-strip:
    backgroundColor: "rgba(9, 9, 10, 0.98)"
    textColor: "#ffffff"
    typography: "{typography.status-secondary}"
    rounded: "{rounded.strip}"
    padding: "6px 8px"
    height: "40px"
    width: "136px"
  status-glyph:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-status}"
    rounded: "{rounded.circular}"
    height: "28px"
    width: "28px"
  shortcut-recorder:
    typography: "{typography.shortcut}"
    width: "112px"
  grouped-field:
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
  permission-row:
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
  history-row:
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
    padding: "10px 0"
---

# Design System: Purrr

## Overview

**Creative North Star: "The Native Proof Strip"**

Purrr is a quiet macOS utility whose visual job is to prove that voice input is alive, progressing, and safe. The system is restrained, compact, and operational: native charcoal or system surfaces, familiar controls, SF Symbols, and concise state language keep the interface subordinate to the user's current work.

Expression comes from one precise signature component and from the quality of state communication, not from a decorative brand layer. Utility windows remain conventional and appearance-adaptive; an opaque charcoal capsule is reserved for the floating transcription strip. Motion is functional and scarce.

**Key Characteristics:**

- Native macOS controls and semantic colors
- Dense grouped utilities with clear hierarchy
- One elevated charcoal control capsule for live transcription
- SF Symbols paired with textual state evidence
- Motion limited to waveform and native progress feedback

## Colors

The palette follows macOS appearance and accent settings; color communicates state rather than brand decoration.

### Primary

- **System Accent** (`{colors.accent}`): Marks the active recording mode, waveform activity, retry activity, focus, and selected native controls. It follows the user's macOS accent rather than imposing a Purrr-specific hue.

### Neutral

- **System Surface** (`{colors.surface}`): Provides the appearance-adaptive foundation for Settings, History, menus, and native fields.
- **Primary Ink** (`{colors.text-primary}`): Carries headings, labels, transcript content, and primary status copy.
- **Secondary Ink** (`{colors.text-secondary}`): Carries supporting explanations, timestamps, elapsed time, and low-priority metadata.
- **Quiet Separator** (`{colors.separator}`): Divides native groups and major regions without creating boxed layouts.

### Semantic Status

- **Success Green** (`{colors.status-success}`): Confirms completed delivery, granted permissions, and successful connections.
- **Attention Orange** (`{colors.status-warning}`): Marks permission action, shortcut warnings, and raw fallback results.
- **Recovery Red** (`{colors.status-error}`): Marks failures and destructive actions.
- **Status White** (`{colors.on-status}`): Keeps symbols legible inside filled status glyphs.

### Named Rules

**The System Owns Appearance Rule.** Use semantic colors so light mode, dark mode, increased contrast, and the user's accent remain authoritative.

**The Status, Not Decoration Rule.** Accent, green, orange, and red exist to communicate interaction or state; do not spread them across passive surfaces.

## Typography

**Display Font:** macOS system sans (`{typography.headline}`)
**Body Font:** macOS system sans (`{typography.body}`)
**Label Font:** macOS rounded system face for time and shortcut evidence (`{typography.status-secondary}` and `{typography.shortcut}`)

**Character:** Typography is platform-native, compact, and factual. Weight changes establish hierarchy; custom typefaces, display treatments, and ornamental tracking are outside the system.

### Hierarchy

- **Headline** (`{typography.headline}`): Window-level identity in History and similarly substantial utility views.
- **Body** (`{typography.body}`): Forms, transcript text, labels, and explanatory copy.
- **Primary Status** (`{typography.status-primary}`): The current action or outcome in compact live-status surfaces.
- **Secondary Status** (`{typography.status-secondary}`): Elapsed time, instruction, countdown, or completion evidence below a primary status.
- **Shortcut Label** (`{typography.shortcut}`): Recorded key combinations and shortcut-capture prompts.

### Named Rules

**The Native Voice Rule.** Use system typography and sentence case; hierarchy comes from weight, semantic style, and spacing rather than display typography.

## Layout

Use native macOS layout behavior and the compact spacing scale in frontmatter. Group related settings in system Forms and Sections; separate major utility regions with dividers; align row actions on the trailing edge. Reserve generous window padding for page-level hierarchy and compact gaps for status, metadata, and inline actions.

The floating strip is a fixed 136-by-40-point status component across Dictate, Translate, processing, success, and failure. A stable frame prevents modes and state transitions from appearing to be unrelated controls. It is centered 12 points above the active screen's usable lower edge, keeping it close to the screen boundary without allowing a persistent Dock to cover it. Settings and History use resizable native windows and should not adopt dashboard grids or web-style breakpoint behavior.

**The Group Before Chrome Rule.** Establish hierarchy with native grouping, alignment, and whitespace before introducing any new container or border.

## Elevation & Depth

The system is flat and tonal by default. Standard windows rely on native title bars, grouped surfaces, separators, and system materials. The transcription strip uses an opaque charcoal surface and a fine inset border so it remains legible over light and dark applications without introducing a clipped rectangular shadow.

### Named Rules

**The One Floating Surface Rule.** Custom charcoal treatment belongs only to the live transcription strip.

## Shapes

Shapes stay inside macOS conventions. The transcription strip uses a true capsule (`{rounded.strip}`); compact state symbols and recording actions use circles (`{rounded.circular}`). Buttons, text fields, toggles, lists, forms, alerts, tabs, and windows keep their native shapes and control metrics instead of receiving a custom radius system.

## Brand Mark

The Purrr mark pairs an asymmetric three-bar voiceprint with a custom geometric `A`, expressing spoken input becoming language. Both halves use the same visual stroke weight, rounded terminals, cap height, and baseline so the pair reads as one compact symbol rather than two adjacent controls. The asymmetry gives the voiceprint a recognizable cadence while the open space before the `A` keeps the mark legible at menu bar size.

The app icon places the mark in fixed Purrr Blue (`{colors.brand-mark}`) on a restrained graphite macOS tile. The menu bar uses the same construction as a monochrome template image with a tighter optical crop. Its `A` receives a small-size optical correction with a lighter stroke so the counter remains open at 16 points; it must follow the system menu bar appearance rather than retain the blue. Do not add a microphone, arrow, divider, enclosing badge, or secondary character to the mark.

## Components

### Buttons

- **Shape:** Use native bordered, borderless, or destructive button styles as the action context requires.
- **Primary:** Purrr has no custom filled brand button. Let macOS provide emphasis and accent behavior.
- **Hover / Focus:** Preserve native pointer, keyboard, focus-ring, disabled, and pressed states.
- **Destructive:** Use the native destructive role and require confirmation for bulk deletion.

### Cards / Containers

- **Corner Style:** Prefer native grouped Forms, inset Lists, Sections, and separators over standalone cards.
- **Background:** Inherit the system surface and current appearance.
- **Shadow Strategy:** Stay flat; only the transcription strip uses elevated depth.
- **Internal Padding:** Use the compact spacing scale and platform defaults rather than oversized card padding.

### Inputs / Fields

- **Style:** Use native rounded-border text fields, secure fields, pickers, toggles, and tab controls.
- **Focus:** Keep the system accent focus ring intact.
- **Error / Disabled:** Pair semantic color with plain-language text or a symbol; never rely on color alone.

### Status Glyphs

State glyphs combine an SF Symbol, a semantic fill, and a textual status. Active recording uses the current mode symbol on System Accent; success and failure use their semantic status colors. The compact circular silhouette remains constant while symbol and color change.

### Shortcut Recorder

The shortcut recorder is a native bordered button with a rounded system label and stable minimum width. Recording state uses explicit prompt text plus the system accent, and Escape exits capture.

### LLM Settings

The settings tab is named **LLM**. API credentials use vertically labeled, full-width fields so values and insertion points remain left aligned. Model selection is populated from the configured endpoint and pairs a native menu Picker with an explicit Load or Refresh action, compact progress evidence, and inline recovery text.

Prompt customization uses one editor rather than two competing text surfaces. A segmented Dictate/Translate control switches the visible prompt, with contextual guidance below the editor and a disabled-until-needed Restore Default action. The Translate prompt documents `{{target_language}}` as its only supported placeholder.

### History Rows

History is a recovery ledger, not a content card collection. Each row combines a state symbol, compact metadata, up to three lines of transcript evidence, and trailing Copy, Retry, or Delete actions; unavailable actions remain visibly disabled.

### Transcription Strip

The signature component is a Typeless-like nonactivating control capsule (`{components.transcription-strip}`). Its ends use circular geometry rather than continuous-corner smoothing, keeping their centers aligned with the circular actions. During recording it presents 28-point circular Cancel and Finish actions around a 44-point input-driven waveform, without explanatory text. Eight points of horizontal inset keep both actions clear of the capsule edge. The waveform is a short history of recent microphone levels instead of a fixed decorative pattern, so speech visibly travels across it and silence settles into quiet dots. The last minute replaces the waveform with a `m:ss` countdown. Recognition and processing use a restrained three-bar activity mark and a short label; success and failure pair a 22-point semantic state glyph with a short label. The state glyph is centered inside the same 28-point leading alignment slot as the recording controls so its center axis remains stable across state changes. Every mode and phase keeps the same outer dimensions, and the hosting view must not derive window geometry from a phase's intrinsic content size. Success remains visible briefly, failures remain visible long enough to read, and the strip never shows live transcript text.

## Do's and Don'ts

### Do:

- **Do** use native macOS controls, semantic colors, system typography, and SF Symbols as the default vocabulary.
- **Do** pair every colored status with a symbol and clear text.
- **Do** keep controls grouped by task and preserve compact utility density.
- **Do** respect Reduce Motion by freezing the waveform while retaining state and level information.
- **Do** keep the transcription strip nonactivating so the user's typing destination remains safe.

### Don't:

- **Don't** introduce a persistent assistant dashboard, decorative brand chrome, or custom navigation shell.
- **Don't** use the custom charcoal capsule treatment outside the floating transcription strip.
- **Don't** replace native controls with web-styled facsimiles or custom focus treatments.
- **Don't** use accent or semantic colors as decoration or as the only carrier of meaning.
- **Don't** add ambient, entrance, or ornamental motion beyond live waveform and native progress feedback.
