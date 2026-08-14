# Build Status

## Current milestone

Vertical Slice 15: Live Fire Beta Foundation.

## Completed vertical slices

- Vertical Slices 1-14 remain implemented: native SwiftUI shell, Dry Fire camera/pose/calibration/recording, deterministic Dry Fire analysis, SwiftData persistence, pose asset storage, Results, Rep Review, Ghost Mode, History, Progress, Personal Records, Personal Baseline, full-session deletion, Analyze & Delete state machine, and bounded maintenance recovery.
- Vertical Slice 15 adds a feature-flagged Live Fire Beta technical foundation: isolated audio-event detection, candidate/accepted/ambiguous/rejected event modeling, deterministic visible-recovery analysis, LiveEvent SwiftData persistence, recovery-window PoseAssets, microphone permission boundary, and synthetic fixture coverage.

## MVP integration/regression audit

- Audit performed after Vertical Slice 15 across Documents 01-07 and current source boundaries.
- `AGENTS.md` was not present; `.agents` contained no additional instructions.
- Document 05 severity model used: P0/P1 release blocker, P2 fix before broad release unless explicitly accepted, P3 deferrable with tracking.
- No approved product behavior or Dry Fire analysis semantics were intentionally changed during the audit.
- No golden fixture values were overwritten.
- Versioning implication reviewed: Live Fire threshold/config additions remain an analysis configuration change (`1.0.0` -> `1.1.0`) with algorithm version preserved at `1.0.0`; persistence schema remains `2` because LiveEvent storage already added schema surface.

## Feature-flag status/default

- `FeatureFlags.production.liveFireBetaEnabled` remains `false`.
- When the flag is off, `TrainRootView` does not expose normal navigation into Live Fire Beta.
- Live Fire UI remains visibly labeled `Live Fire Beta` and `Visible Movement & Recovery` when enabled by configuration.
- Live Fire is not approved for external testers by this slice.

## Development workflow requirement

- The approved development environment is Windows + VS Code + Codex.
- Local Xcode usage is not a project requirement and should not be requested for ordinary implementation, review, documentation, or regression-audit work.
- Native iPhone/TestFlight validation remains required for Apple-framework behavior, but it must be handled through a remote/cloud/CI Apple-compatible build path or another explicit handoff.

## Files/components created or changed

- `DryFireVision/Domain/LiveFire/AudioEventModels.swift`
- `DryFireVision/Domain/LiveFire/LiveFireAnalysisModels.swift`
- `DryFireVision/Domain/LiveFire/LiveFireRecoveryAnalyzer.swift`
- `DryFireVision/Services/AudioEventDetection/MicrophonePermissionProviding.swift`
- `DryFireVision/Features/LiveFire/LiveFireBetaViewModel.swift`
- `DryFireVision/Features/LiveFire/LiveFireBetaSetupView.swift`
- `DryFireVision/Features/Train/LiveFireBetaPlaceholderView.swift` removed
- `DryFireVision/Features/Train/TrainRootView.swift`
- `DryFireVision/App/AppShellView.swift`
- `DryFireVision/App/DependencyContainer.swift`
- `DryFireVision/Domain/Analysis/AnalysisConfiguration.swift`
- `DryFireVision/Shared/Versioning/VersionCatalog.swift`
- `DryFireVision/Persistence/Models/PersistedLiveEventRecord.swift`
- `DryFireVision/Persistence/Models/PersistedTrainingSession.swift`
- `DryFireVision/Persistence/Models/PersistedPoseAssetRecord.swift`
- `DryFireVision/Persistence/Migrations/DryFireVisionPersistenceSchema.swift`
- `DryFireVision/Persistence/Repositories/SessionRepository.swift`
- `DryFireVision/Persistence/Repositories/SwiftDataSessionRepository.swift`
- `Tests/Fixtures/LiveFireSyntheticFixtures.swift`
- `Tests/Domain/AudioEventDetectorTests.swift`
- `Tests/Domain/LiveFireRecoveryAnalyzerTests.swift`
- `Tests/Domain/LiveFireBetaViewModelTests.swift`
- `Tests/Domain/VersionCatalogTests.swift`
- `Tests/Integration/SwiftDataSessionRepositoryTests.swift`

## Microphone permission architecture

- Added `MicrophonePermissionProviding` with `notDetermined`, `authorized`, `denied`, and `restricted`.
- `SystemMicrophonePermissionProvider` uses `AVAudioSession` only on iOS.
- Microphone permission is checked/requested only inside the Live Fire Beta setup flow after user acknowledgement.
- Dry Fire camera/setup/recording remains independent of microphone permission.
- Denied/restricted microphone state shows recovery copy and Settings guidance.

## Synchronized capture/timestamp architecture

- Added `LiveFireSynchronizedInput` as the deterministic boundary for synchronized audio samples, pose frames, normalization scale, and configuration.
- All Live Fire detector/recovery math uses sample/frame timestamps in seconds.
- No UI timers, array-index timing, fixed FPS assumptions, wall-clock event timing, or cloud/audio ML were introduced.
- Real AVFoundation synchronized camera+microphone capture is not implemented/validated in this Windows slice; the foundation is synthetic-input ready and must be connected/validated on device.

## AudioEventDetector implementation

- `AudioEventDetector` is isolated from Dry Fire `MovementStateMachine` and `RepSegmenter`.
- Detection is deterministic amplitude/transient thresholding over timestamped `AudioSignalSample` values.
- Configuration fields added under `AnalysisConfiguration`:
  - impulse threshold
  - high/medium confidence thresholds
  - debounce window
  - minimum event spacing
  - pre/post recovery windows
  - recovery tolerance/dwell
  - Live pose coverage/gap thresholds
- Debounce collapses ringing/echo inside the configured window.
- Minimum spacing collapses neighboring impulses into one ambiguous candidate rather than multiple accepted events.
- Clipped/saturated impulses are downgraded to ambiguous.
- Candidate IDs are timestamp-derived for deterministic repeated analysis.

## Event confidence and status policy

- Domain models distinguish candidate audio events from analyzed Live events.
- Status values: `accepted`, `ambiguous`, `rejected`.
- Confidence values reuse `ConfidenceStatus.high/medium/low`.
- Accepted events can produce primary recovery metrics.
- Ambiguous/rejected events are retained in event lists but do not produce confident recovery claims.
- Event confidence is separate from recovery confidence.

## Recovery analysis

- `LiveFireSessionAnalyzer` extracts bounded recovery windows around accepted event timestamps.
- Pre-event baseline uses median high-confidence nose/left-shoulder/right-shoulder samples immediately before the event.
- Peak Visible Displacement is the maximum normalized selected upper-body displacement after the event within the configured post-event window.
- Recovery begins after peak displacement.
- Recovery duration is recovered timestamp minus event timestamp.
- Recovered state requires displacement within tolerance for a timestamp-based dwell window.
- Missing baseline, insufficient pose coverage, pose gaps, invalid normalization, or no recovered state produces unavailable/degraded metrics rather than fabricated values.
- Recovery trajectories are compact `RecoveryTrajectorySample` values and can be compared deterministically.
- Recovery similarity/consistency is repeatability-oriented, internal, and not a technique/accuracy score.
- Outliers are session-relative using existing robust median/MAD style thresholds.

## LiveEvent persistence

- Added `PersistedLiveEventRecord` and `PersistedTrainingSession.liveEvents`.
- Live sessions persist with `TrainingSession.mode == liveFire`.
- LiveEvent round-trip includes status, event confidence, timestamp, inter-event duration, visible displacement metrics, recovery duration, recovery similarity, recovery confidence, outlier flag, reason, analysis version, and config version.
- Recovery-window PoseAssets persist with `PoseAssetType.recoveryWindow`.
- Live metric values are not placed into Dry Fire `averageRepDuration` or Dry Fire movement-consistency fields.
- Live Fire recovery consistency is reconstructed from persisted accepted-event recovery similarity during fetch so Dry Fire aggregate fields remain uncontaminated.
- History can show a Live Fire Beta mode badge through existing mode mapping, but Live trend charts were not added.

## Media retention behavior

- `SessionRepository.saveLiveFire` reuses Slice 14 Keep Video / Analyze & Delete media lifecycle.
- Live raw media is never deleted before LiveEvent persistence and recovery PoseAssets commit.
- Current production raw-video capture is still absent, so real sessions continue to be `notRecorded` unless a future app-owned raw media reference is supplied.

## Live Results/Event Review scope

- Implemented beta setup/permission foundation and domain/persistence result models.
- A full production Live Results screen and Event Review playback UI are not yet complete.
- Event Review foundation exists through recovery-window PoseAssets; pose-only fallback is persistence-ready but not rendered in a dedicated Event Review screen.

## Fixtures created

Synthetic fixture IDs:
- `LF_CLEAN_5`
- `LF_VARIABLE_RECOVERY`
- `LF_BACKGROUND_ONLY`
- `LF_MIXED_NOISE`
- `LF_CLIPPED_AUDIO`
- `LF_CAMERA_MOVED`
- `LF_POSE_OCCLUDED`

These are synthetic audio/pose fixtures only. They are not field recordings and are not evidence of real range behavior.

## Automated tests/checks

Added tests for:
- no impulse -> zero candidates
- one clean transient -> accepted candidate
- ringing inside debounce -> one candidate
- separated impulses -> two candidates
- clipped transient -> ambiguous
- repeated detector analysis deterministic
- clean five-event recovery fixture
- variable recovery durations
- background-only fixture produces no accepted/confident recovery
- pose occlusion suppresses recovery
- invalid normalization suppresses recovery
- Live Fire acknowledgement checks microphone status without requesting permission immediately
- denied microphone enters recovery state
- Live Fire session persistence round-trip with LiveEvent records and recovery-window PoseAssets
- Live Fire persistence preserves deterministic event IDs and available recovery consistency across round-trip
- version catalog updated for schema/config changes

Checks actually run in this Windows environment:
- Source search for stale placeholder references, Live Fire symbols, version expectations, and invalid metric reasons.
- `swift test` attempted and failed because Swift is not installed.
- Local Xcode and iOS simulator commands are no longer part of the approved project workflow. Native iPhone/TestFlight validation must be performed through a remote/cloud/CI Apple-compatible build path or another explicit handoff.

## Audit defects fixed

- P1: Live Fire event analysis IDs were generated randomly instead of inheriting deterministic candidate IDs, weakening repeatable fixture results and recovery-window pose asset mapping. Fixed by passing candidate IDs into accepted and unavailable Live events. No analysis/configuration/schema version change required because metric formulas and persisted schema did not change.
- P2: Live Fire recovery consistency was available immediately after analysis but reloaded as unavailable after persistence because Dry Fire aggregate fields are intentionally not reused for Live metrics. Fixed by reconstructing the Live-only consistency aggregate from persisted event similarities on fetch. No schema change or golden rewrite required.
- P3: The Live Fire microphone acknowledgement test relied on a single cooperative task yield and could be timing-sensitive. Fixed with a bounded wait for state transition without weakening assertions.

## Dry Fire regression results

- Full Dry Fire regression suite was not executable in this Windows environment.
- Source-level review preserved Dry Fire feature flag default, Dry Fire setup/camera flow, Dry Fire analyzer/repository calls, Progress filtering, Rep Review, Ghost Mode, and Analyze & Delete boundaries.
- Analyze & Delete ordering remains source-reviewed as persist-analysis/save-assets/commit before raw media deletion; deletion failure remains represented as `deletionFailed`, not silently `deleted`.
- Progress source review continues to filter trends by mode and compatible analysis version, preserving Dry Fire/Live separation and preventing incompatible analysis versions from sharing trend baselines.
- Automated regression execution remains required from Windows + VS Code where the toolchain supports it, plus native iPhone/TestFlight validation through the approved external build path.

## Schema/migration changes

- Persistence schema version changed from `1` to `2`.
- Analysis configuration version changed from `1.0.0` to `1.1.0`.
- Added SwiftData model `PersistedLiveEventRecord` and relationship `PersistedTrainingSession.liveEvents`.
- No destructive reset or migration execution was performed here; old Dry Fire store migration must be validated through the approved external Apple-compatible build/TestFlight path before release.

## Native/TestFlight/physical-device validation

- Not performed.
- Required later through the approved external Apple-compatible build path: microphone permission prompt behavior, real synchronized AV capture, audio/video/pose timestamp relationships, real acoustic signal stability, camera/pose behavior, Analyze & Delete with real media, Event Review load, thermal/performance, and TestFlight install validation.

### Required iPhone/TestFlight smoke checklist

- Install a fresh TestFlight build on one current supported iPhone and one older supported iPhone.
- Launch offline/airplane mode and confirm Home, Settings privacy/version details, and empty History/Progress render without network.
- Deny camera permission, confirm recoverable copy and safe navigation; then re-enable camera permission from Settings.
- Complete onboarding, calibration, and one 10-rep Dry Fire session with Keep Video; verify Results, Rep Review, Ghost Mode, History detail, Progress trend/baseline, and app relaunch persistence.
- Complete a second 10-rep Dry Fire session with Analyze & Delete; verify results persist, raw media is removed only after persistence succeeds, History still opens, and no missing-media crash occurs.
- Delete one completed session from History and confirm owned media/pose assets are removed while remaining History/Progress records recalculate.
- Install/upgrade over a build containing an older schema-1 Dry Fire store and confirm migration preserves completed sessions, reps, pose assets, video retention state, History, and Progress.
- Confirm production/default configuration does not expose Live Fire Beta navigation.
- With Live Fire Beta explicitly enabled for internal testing, acknowledge the beta screen, verify microphone status is checked before prompting, request microphone permission only from the Live Fire flow, and confirm denied/restricted states recover safely.
- With Live Fire Beta enabled on device, run controlled non-range impulse tests to inspect audio/video/pose timestamp alignment, event confidence, ambiguous/rejected event handling, and recovery-window pose asset loading.
- Confirm thermal/performance remains acceptable during recording, processing, Results, Rep Review, Ghost Mode, History, and Live Fire Beta smoke paths.

## Controlled acoustic / field testing

- Controlled acoustic validation was not performed with hardware.
- Field/range testing was not performed.
- Synthetic tests are only deterministic algorithm checks.

## Performance/thermal observations

- No physical performance, memory, battery, drift, thermal, or Event Review load measurements were collected.

## Known limitations

- Real synchronized AVFoundation camera+microphone capture is not implemented in production UI.
- Full Live Fire recording UI, manual End Session capture flow, production Live Results, and Event Review screens remain incomplete.
- Camera-movement handling is represented as a fixture/reason foundation, not a validated camera-movement detector.
- Background-noise handling is conservative but synthetic only; false-positive/false-negative rates are unknown.
- Recovery similarity/consistency is an initial deterministic foundation and requires controlled validation before user-facing claims.
- Live Fire quality gates are not satisfied.

## Unresolved audit defects / release gates

- P1: Automated Swift/XCTest execution could not be completed in the current Windows environment because Swift is not installed. This is a release blocker until the Windows/VS Code toolchain or CI runs the suite successfully.
- P1: Native iPhone/TestFlight validation has not been completed through the approved external Apple-compatible build path. Local Xcode is not a project requirement.
- P1: Persistence schema v2 migration from existing schema-1 Dry Fire stores is not validated through an Apple-compatible build/TestFlight path or representative on-device stores. This is a release blocker before TestFlight/broad release.
- P1: Analyze & Delete with real app-owned video capture media is not physically validated because production raw-video capture is still absent from this environment.
- P1: Live Fire microphone/camera synchronized capture, timestamp alignment, device permissions, and acoustic behavior are synthetic-only and not release-gate complete.
- P2: Production Live Fire Results and Event Review screens remain incomplete by design for the beta foundation slice; Live Fire must remain disabled by default.

## Beta release gates

- Document 05 Live Fire Beta release gates are not satisfied.
- Live Fire remains disabled in production/default configuration.
- External enablement requires explicit approval after native/device/control/field validation.

## MVP release-gate status

- Dry Fire MVP is not cleared for release from this audit because automated Swift/XCTest execution, external native-device/TestFlight validation, schema migration validation, and physical smoke testing remain incomplete.
- Live Fire Beta is not cleared for external testers and remains behind the disabled-by-default feature flag.

## Prohibited scope confirmation

- No Dry-vs-Live comparison, equipment/firearm tracking, ballistics, shot placement, physical recoil-force measurement, StoreKit, CloudKit, backend, custom ML, AI coaching, social features, or share/export functionality was intentionally implemented.

## Specification conflicts / unresolved decisions

- No blocking specification conflict was found.
- Product decisions still needed: exact real AV capture architecture, Event Review UI scope, external beta enablement policy, migration strategy validation for existing user stores, and acceptable field false-positive/false-negative thresholds.

## Bugs / regression fixture IDs

- No confirmed regression fixture failures in this environment.
- New Slice 15 tests await Windows Swift toolchain or CI execution.

## Next milestone

Dry Fire MVP / Live Fire Beta Release-Gate Review.
