# Binary Release Checklist

Purrr currently distributes source only. This checklist applies before publishing a supported, downloadable macOS app; see [README.md](../README.md) for the current build instructions and prototype limitations.

## Before Publishing an App

- [ ] Collect and package applicable license texts, copyright notices, and required notices for the exact linked Rust and native dependencies, including Opus. Include Purrr's MIT license and verify the completed third-party notice bundle.
- [ ] Review current dependency advisories and the pinned speech provider. Address or document unresolved risks, and assess remote-service terms and authorization separately from source-code licensing.
- [ ] Sign with a Developer ID Application identity, enable the required hardened runtime, notarize, and staple the release. Development and ad-hoc signatures are not release signatures.
- [ ] Scan the final executable, resources, and distribution archive for credentials and local build paths. A clean Git history does not establish that build artifacts are clean.
- [ ] Test on a fresh Apple Silicon Mac or account without developer state, including the minimum supported macOS version: first-run permissions, shortcut conflicts, Dictate with LLM off/on, Translate, cancellation, focus changes, provider failure, retry, clipboard fallback, and history expiry after relaunch.
- [ ] Publish installation, update, uninstall, and known-limitation instructions. Never ask users to disable Gatekeeper globally.

## Known Dependency and Build Risks

- The pinned Koe integration uses `audiopus_sys` 0.2.2, which is flagged as unmaintained by [RUSTSEC-2026-0150](https://rustsec.org/advisories/RUSTSEC-2026-0150.html). Replacing it requires speech-bridge regression checks; successful compilation does not resolve the maintenance risk.
- The bridge statically links the installed native Opus library. `Cargo.lock` does not pin that library's version; record and review the exact version used for each binary release and its required notices.
- Rust binaries may embed source-location strings from Cargo caches and build directories. Apply path remapping and scan the final distribution artifact before binary publication.

See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) for the retained Koe license notice. It is not yet a complete binary dependency notice bundle.
