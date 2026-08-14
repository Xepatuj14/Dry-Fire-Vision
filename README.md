# Dry Fire Vision

Dry Fire Vision is a native Swift/SwiftUI iPhone application for dry-fire movement-performance analysis.

## Repository Layout

- `DryFireVision/App`: composition root, app shell, feature flags, routing.
- `DryFireVision/Features`: SwiftUI feature surfaces.
- `DryFireVision/Domain`: deterministic domain types and future analysis logic.
- `DryFireVision/Services`: service boundaries for camera, pose detection, media, audio, and analysis pipeline work.
- `DryFireVision/Persistence`: repository, model, asset-store, and migration boundaries.
- `DryFireVision/Shared`: shared UI, logging, utilities, and versioning.
- `Tests`: future domain, integration, UI, and fixture test structure.
- `UXPrototype`: optional Expo Go UI/UX prototypes only. This is not production source.

## Windows + VS Code Workflow

The primary development workflow is Windows + VS Code + Codex. Use this environment for source editing, documentation updates, Git work, architecture changes, and deterministic domain/test development.

Expo Go may be used only for rapid UI/UX prototyping. Approved prototype behavior must be recreated in native SwiftUI before it is considered production implementation.

## Validation Boundaries

Windows + VS Code is the required project workflow. Do not require local Xcode use for ordinary source editing, implementation, documentation, Git work, or audit/regression review.

Windows-side validation can inspect source, documentation, repository layout, deterministic fixtures, and other platform-independent checks. If a Swift toolchain is installed on Windows, run the pure Swift/package-compatible tests from VS Code or the terminal.

iPhone/TestFlight validation is still required for native-device behavior, but it must be handled through a remote/cloud/CI Apple-compatible build path or another explicit handoff, not by assuming this project will be opened or developed in Xcode.

The native-device validation boundary covers:

- iOS compilation and linking.
- SwiftUI runtime validation on device/TestFlight.
- Code signing, provisioning, archives, and TestFlight distribution.
- AVFoundation, Vision, SwiftData, microphone, permission, performance, thermal, and physical-device validation.

Do not treat Expo Go review or Windows source checks as evidence that native iOS behavior has been validated.

## Current Slice

Vertical Slice 15 is the current implementation ledger.

Implemented source now includes:

- Native SwiftUI shell, Dry Fire camera/pose/calibration/recording, deterministic analysis, Results, Rep Review, Ghost Mode, History, Progress, and persistence.
- Analyze & Delete media lifecycle and bounded maintenance recovery.
- Feature-flagged Live Fire Beta foundation with synthetic audio/pose fixtures, microphone permission boundary, LiveEvent persistence, and recovery-window pose assets.
- Audit updates for deterministic Live Fire IDs and Live Fire recovery consistency round-trip.

Native iPhone/TestFlight validation remains required for camera, pose, persistence, permissions, and performance behavior, but it is an external validation/build step rather than a local Xcode workflow.

See `BUILD_STATUS.md` for the current implementation ledger, checks run, known limitations, and the recommended next slice.
