# Build Status

## Current milestone

GitHub Actions Native iOS CI / TestFlight Pipeline.

## Latest implementation update: Dry Fire Movement Consistency primary-wrist config

- Fixed Movement Consistency showing `Insufficient Data` for otherwise valid Dry Fire sessions because the configurable session path rebuilt `AnalysisConfiguration` without `primaryWristJointID`.
- The canonical Dry Fire V1 primary wrist is `.rightWrist`, matching existing comparison fixtures, metric fixtures, Rep Review expectations, and Ghost Mode V1.
- Added `AnalysisConfiguration.dryFireV1` as the centralized standard Dry Fire analysis configuration with `.rightWrist`.
- `DryFireSessionConfiguration.analysisConfiguration` now starts from `AnalysisConfiguration.dryFireV1` and overrides only the selected maximum rep-window duration plus version suffix, preserving comparison fields and thresholds.
- Added bounded comparison unavailable reason `missingPrimaryWristConfiguration` so missing comparison configuration is no longer indistinguishable from genuine insufficient user data.
- Results text still shows normal insufficient-data cases as `Insufficient Data`, but internal/configuration comparison failures now show `Consistency Unavailable`.
- Ghost Mode maps the new bounded reason to its existing primary-wrist-unavailable state without changing Ghost comparison behavior.
- No similarity formulas, comparison thresholds, calibration behavior, camera behavior, persistence schema, or handedness UI were changed.

Checks run in the Windows environment:

- Added/updated tests for standard Dry Fire config carrying `.rightWrist`, rep-window overrides preserving canonical comparison config, session length not affecting comparison config, comparison joint set availability, valid fixtures producing available Movement Consistency, and missing primary wrist reporting `missingPrimaryWristConfiguration`.
- Added a pipeline-level regression proving `DryFireSessionConfiguration` produces available Movement Consistency on the existing good 10-rep fixture.
- `git diff --check` passed.
- `swift test --filter DryFireSessionConfigurationTests` could not run because `swift` is not available on this Windows PATH.
- `swift test --filter SessionComparisonAnalyzerTests` could not run because `swift` is not available on this Windows PATH.

Native iPhone/TestFlight validation still required:

- Complete 5-rep and 10-rep Dry Fire sessions and confirm Movement Consistency is available for normal valid sessions.
- Confirm low-quality/occluded sessions still show conservative insufficient-data states rather than fabricated consistency.
- Confirm final-rep auto-end, rep windows, calibration Ready behavior, front/rear camera behavior, and front-camera mirroring remain intact.

## Latest implementation update: Dry Fire final-rep auto-end buffer

- Added an explicit post-target `finishingSession` recording state for Dry Fire sessions.
- Automatic target-rep completion is detected in `CameraFlowViewModel` after live segmentation reports `completedValidRepCount >= targetRepCount`.
- The final-rep completion buffer is centralized as `PoseRecordingConfiguration.finalRepCompletionBufferSeconds`, defaulting to `1.5` seconds.
- The final buffer starts only after a valid accepted rep has reached segmentation completion and the target count is satisfied.
- During the final buffer, the UI shows "Session Complete" / "Finishing analysis..." and the rep counter remains bounded at the configured target.
- During `finishingSession`, incoming pose callbacks are not accepted into live segmentation, so Rep 6 of 5 / Rep 11 of 10 cannot arm or increment the accepted count.
- Invalid/timed-out attempts remain rejected by existing `RepValidity`/segmentation rules and do not count toward target completion.
- Finalization is idempotent through a single `finalRepCompletionTask`; repeated target callbacks after the state changes cannot schedule another finish.
- Manual Stop still uses the existing safe `PoseRecordingService.finish()` path and cancels any pending final-buffer task.
- No calibration thresholds, movement metric formulas, camera behavior, front-camera mirroring, persistence schema, or unrelated flows were changed.

Checks run in the Windows environment:

- Added camera-flow tests for final buffer starting only after final rep completion, invalid timeout attempts not satisfying target, no next rep during final buffer, and repeated callbacks after completion leaving the completed recording stable.
- Updated 5-rep and 10-rep automatic completion tests to exercise the configurable final buffer.
- `git diff --check` passed.
- `swift test --filter CameraFlowViewModelTests` could not run because `swift` is not available on this Windows PATH.

Native iPhone/TestFlight validation still required:

- Complete 5-rep and 10-rep Dry Fire sessions and confirm the app enters finishing immediately after the final accepted rep completes, waits about 1.5 seconds, then advances to Processing/Results.
- Confirm invalid/timed-out attempts do not end the session early.
- Confirm moving during the final buffer does not arm or record an extra rep.
- Confirm interruption/background handling during the final buffer follows the existing safe interruption/finalization behavior.

## Latest implementation update: Dry Fire configurable session length and rep window

- Added Dry Fire setup selectors for Session Length (`5 Reps`, `10 Reps`) and Rep Window (`2 sec`, `3 sec`, `5 sec`, `10 sec`).
- Defaults are `10 Reps` and `5 sec`.
- Added `DryFireSessionConfiguration` as the single setup/session configuration source for `targetRepCount` and `maximumRepDurationSeconds`.
- The selected target rep count now flows into the camera flow, processing input, analysis, results, and persisted session `targetRepCount` through the existing analysis/persistence path.
- The selected maximum rep window now flows into segmentation through `AnalysisConfiguration.plausibleRepDurationMaximumSeconds`.
- The selected maximum rep window is retained for historical provenance through the existing persisted `analysisConfigurationVersion` string, using a suffix such as `+repWindow5s`; no persistence schema migration was added.
- Current continuous-timer root cause confirmed: live recording was only accepting pose frames and displaying overall elapsed recording time; rep segmentation and target-rep evaluation were deferred until manual Stop/processing, and `CameraFlowView` hard-coded `targetRepCount: 10` for processing.
- Live recording now segments accepted frames with the selected configuration and automatically finishes capture when valid accepted reps reach the configured target.
- Timeout behavior is implemented in `MovementStateMachine`: once a confirmed active rep exceeds the configured maximum duration, that attempt is rejected as invalid with `repWindowExceeded`, the segmenter transitions to reset/recovery, and the attempt does not count toward target completion.
- The rep window starts only after confirmed movement start (`READY -> MOVING`); it does not run during calibration, countdown, waiting for the starting stance, or Ready with no movement.
- Timeout does not fabricate a successful fixed-duration rep. Actual completed rep duration remains the measured segment duration.
- Manual Stop remains available as an early finish path.
- No calibration thresholds, movement formulas, camera behavior, skeleton mirroring, Ghost Mode, Live Fire, persistence schema, or unrelated UI flows were intentionally changed.

Checks run in the Windows environment:

- Added configuration tests for defaults, 5/10 rep selection, and 2/3/5/10 second rep-window mapping.
- Added movement state-machine tests for normal completion before timeout, active-rep timeout, and timeout not starting while Ready.
- Added camera-flow tests for automatic five-rep completion, automatic ten-rep completion, and Start-button excursion longer than the rep window not creating a timeout before recording arms.
- `git diff --check` passed.
- `swift test --filter DryFireSessionConfigurationTests` could not run because `swift` is not available on this Windows PATH.
- `swift test --filter MovementStateMachineTests` could not run because `swift` is not available on this Windows PATH.

Native iPhone/TestFlight validation still required:

- Verify 5-rep and 10-rep Dry Fire sessions automatically advance to processing/results at the selected target count.
- Verify 2/3/5/10 second rep windows reject only active incomplete attempts and do not alter measured durations for completed reps.
- Verify invalid/timed-out attempts do not count toward target completion.
- Verify countdown, waiting-for-start-position, baseline locking, front/rear camera selection, and front-camera skeleton mirroring remain intact.

## Latest implementation update: Dry Fire front-camera skeleton mirroring

- Fixed the front-facing camera skeleton overlay appearing horizontally reversed relative to the mirrored selfie preview.
- Root cause confirmed: the front camera preview layer is explicitly mirrored for natural selfie behavior, while the calibration skeleton overlay was rendering canonical unmirrored pose coordinates directly through the aspect-fill mapper.
- The fix keeps Vision/domain pose coordinates canonical and camera-independent; it does not swap anatomical left/right joint identities or alter analysis inputs.
- Front-camera overlay rendering now applies a display-only horizontal mirror before the existing aspect-fill projection: `displayNormalizedX = 1.0 - normalizedX`.
- Rear-camera overlay rendering remains unchanged: `displayNormalizedX = normalizedX`.
- Existing preview aspect-fill crop/offset behavior is preserved for both camera positions.
- AVFoundation sample-buffer output remains unmirrored for pose analysis; only the preview layer and matching display overlay are mirrored for the front camera.
- No movement-analysis formulas, calibration thresholds, stability timing, rep segmentation, persistence schema, Ghost Mode, Live Fire, or broad UI behavior was changed for this fix.

Checks run in the Windows environment:

- Source-reviewed `CameraPreviewView`, `AVFoundationCameraCaptureProvider`, `VisionPoseDetector`, `PoseObservationMapper`, `CalibrationPreviewView`, and the overlay mapper boundary.
- Confirmed the front preview sets `connection.isVideoMirrored = true` only for `CameraPosition.front`.
- Confirmed Vision pose detection uses the capture sample buffer with orientation `.right` and no camera-position mirror transform.
- Added focused aspect-fill overlay mapping tests for rear/unmirrored mapping, front/display-mirrored mapping, center-point behavior, and the no-double-mirror regression.
- Confirmed existing `PoseObservationMapperTests` preserve anatomical joint identity (`leftWrist` remains `leftWrist`) and canonical coordinate conversion.
- `swift test --filter AspectFillPoseOverlayMapperTests` could not be executed locally because `swift` is not available on this Windows PATH.

Native iPhone/TestFlight validation still required:

- Confirm rear-camera skeleton markers and bones remain aligned while raising left/right arms, moving left/right, and leaning left/right.
- Confirm front-camera skeleton markers and bones align with the mirrored selfie preview for the same movements.
- Confirm switching cameras does not leave a stale mirror state active.
- Confirm calibration framing, joint markers, skeleton bones, and any movement-path overlays using this mapping remain visually aligned.

## Latest implementation update: Dry Fire calibration Ready latch

- Fixed the Ready-state calibration loop where a solo user could complete calibration, walk toward the phone to tap Start, and have normal body movement invalidate the successful calibration before recording could begin.
- Once Dry Fire calibration reaches Ready, the captured calibration baseline and normalization data are now latched for the setup session.
- Normal body movement after Ready no longer feeds back into full calibration evaluation or captures a replacement neutral baseline.
- The Start button remains available after Ready while the user approaches the phone.
- Countdown still uses the existing configured duration.
- Root cause of the post-countdown arming regression: the previous recovery path only checked a single return-to-baseline frame and started recording from that frame, which did not guarantee the recorded pose stream contained the stable near-baseline window required for the rep state machine's `WAITING_FOR_STABLE -> READY` transition.
- When Start is pressed, a bounded recording-arm tracker now starts fresh from the latched calibration baseline; Start-button excursion frames are excluded from the recording-arm buffer.
- During countdown and `waitingForStartPosition`, the tracker requires required-joint visibility, adequate confidence, similarity to the accepted baseline using the existing normalized baseline-distance concepts, and a stable window using the existing recording readiness thresholds.
- Recording starts from the first frame of the stable return-to-baseline window, preserving enough initial stable samples for the offline segmentation state machine to reach `READY` before the first real movement.
- If the user is not back in position when countdown finishes, the app enters a `waitingForStartPosition` recovery state with the instruction "Return to your starting position." The latched calibration is preserved and recording begins once the user returns and remains stable near the stored baseline.
- Camera switching and leaving/cancelling setup still invalidate calibration through the existing reset paths.
- No calibration timing algorithm, stability thresholds, movement-analysis formulas, pose-analysis cadence, rep segmentation, Ghost Mode, Live Fire, persistence schema, or broad UI design was changed for this fix.

Checks run in the Windows environment:

- Added focused CameraFlowViewModel regression tests for Ready latching after movement, baseline preservation after Ready, countdown verification against the latched baseline, waiting-for-start-position recovery, user-never-returns behavior, recording after a stable return window, and first-rep segmentation after a Start-button excursion.
- Source-reviewed the existing camera-switch reset path to confirm switching still invalidates calibration.
- Swift/Xcode tests could not be executed locally because `swift` and `xcodebuild` are not available on this Windows PATH.

Native iPhone/TestFlight validation still required:

- Complete calibration, walk to the phone after Ready, confirm Start remains available, tap Start, and verify countdown/recovery behavior on a physical iPhone.
- Confirm recording does not begin until the user returns close to the calibrated starting pose and remains stable long enough to arm recording.
- Confirm the Start-button excursion is not counted as Rep 1 and the first intentional movement after arming is detected normally.
- Confirm camera switching or leaving setup still requires a fresh calibration.

## Latest implementation update: Dry Fire front/rear camera selection

- Dry Fire calibration now defaults to the front-facing camera for a new calibration flow.
- Calibration preview exposes a standard camera-flip control while camera switching is permitted.
- Switching between front and rear cameras restarts capture, clears any current calibration baseline, and restarts pose/framing evaluation.
- Camera switching is locked after calibration reaches Ready and remains unavailable during countdown, recording, and processing.
- Front-camera preview mirroring is applied only to the preview layer; Vision/domain pose coordinates are not mirrored or transformed.
- Dry Fire recording metadata now carries the selected `cameraPosition`, and the existing persisted `PersistedTrainingSession.cameraPosition` field is populated with `front` or `rear`.
- No movement-analysis formulas, calibration thresholds, pose confidence rules, rep segmentation, Live Fire, Ghost Mode, schema model fields, or navigation flows were changed for this update.

Checks run in the Windows environment:

- Source-reviewed AVFoundation camera input selection and preview mirroring boundaries.
- Added focused tests for default front camera selection, switching to rear, calibration invalidation on switch, switch lockout during countdown, completed-recording camera metadata, and persisted session camera position.
- Swift/Xcode tests could not be executed locally because `swift` and `xcodebuild` are not available on this Windows PATH.

Native iPhone/TestFlight validation still required:

- Confirm front and rear camera capture both start successfully on physical iPhones.
- Confirm the front preview feels naturally mirrored while pose skeleton alignment and analysis coordinates remain correct.
- Confirm switching before calibration clears the previous baseline and recalibrates cleanly.
- Confirm the flip control disappears or is unavailable after Ready, during countdown, during recording, and through processing.
- Confirm completed sessions persist `cameraPosition` as `front` or `rear`.

## Infrastructure milestone: GitHub Actions Native iOS CI / TestFlight Pipeline

- Created `.github/workflows/ios-testflight.yml`.
- Workflow runner image is `macos-15`.
- Workflow triggers are manual `workflow_dispatch` with `upload_to_testflight` defaulting to `false`, plus `push` to `main` for build validation.
- Workflow uses `actions/checkout@v4` and `actions/upload-artifact@v4`.
- Workflow permissions are explicitly limited to `contents: read`.
- The workflow lists available Xcode installations and selects the newest available Xcode on the runner.
- Project/scheme are `DryFireVision.xcodeproj` and `DryFireVision`; application target is `DryFireVision`.
- Archive command uses generic iOS device destination, `Release`, `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`, and CI-supplied `DFV_BUNDLE_IDENTIFIER`, `APPLE_TEAM_ID`, and `DFV_PROVISIONING_PROFILE_SPECIFIER`.
- Export uses a dynamically generated CI-only `ExportOptions.plist` with `method = app-store-connect`, manual signing, and bundle-ID-to-profile mapping.
- Exported IPA is expected under `build/export/`.
- Build artifact is named `DryFireVision-iOS-${{ github.run_number }}` and includes the IPA plus useful build logs.
- TestFlight upload is gated behind manual `upload_to_testflight = true` and uses `xcrun altool` with App Store Connect API key authentication.
- Required signing/upload secret names are documented: `DFV_BUNDLE_IDENTIFIER`, `APPLE_TEAM_ID`, `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `BUILD_PROVISION_PROFILE_BASE64`, `DFV_PROVISIONING_PROFILE_SPECIFIER`, `KEYCHAIN_PASSWORD`, `APPSTORE_API_KEY_ID`, `APPSTORE_ISSUER_ID`, and `APPSTORE_API_PRIVATE_KEY`.
- The workflow installs signing assets only into temporary runner locations/keychains and cleans temporary certificate, profile, keychain, ExportOptions, and App Store Connect key files in an `always()` cleanup step.
- `docs/IOS_CI_BUILD.md` now documents manual run instructions, build-only mode, build+TestFlight mode, artifact naming/location, secret checklist, signing/profile installation, export strategy, troubleshooting, and the Windows-to-GitHub-to-macOS handoff.

Checks run in the Windows environment:

- Read Document 07 engineering guidance, `docs/IOS_CI_BUILD.md`, `BUILD_STATUS.md`, `.gitignore`, `DryFireVision.xcodeproj`, and the shared scheme.
- Confirmed `AGENTS.md` is not present.
- Inspected project build settings for bundle identifier indirection, signing placeholders, generated Info.plist, iOS 17.0 deployment target, camera/microphone usage descriptions, AppIcon setting, versions, app target, and product type.
- Inspected shared scheme for build/archive support.

Checks requiring GitHub macOS runner:

- YAML execution by GitHub Actions.
- Xcode project loading with the selected macOS/Xcode image.
- `xcodebuild -list`, `swift test`, archive, export, and artifact upload.
- Certificate/profile import, manual code signing, App Store Connect API-key authentication, and TestFlight upload.

Unresolved CI/TestFlight prerequisites:

- Repository secrets must be configured.
- The `DFV_BUNDLE_IDENTIFIER` secret should be set to the approved value `com.clarkiioutdoors.dryfirevision`.
- CI signing certificate and provisioning profile must match the Apple team, bundle identifier, and profile specifier.
- A temporary development AppIcon image exists for CI asset compilation; final App Store-ready AppIcon artwork remains required before release.
- The first GitHub macOS run has not yet validated archive/export/TestFlight.

No Dry Fire product behavior, Live Fire behavior, analysis algorithms, UX flows, persistence schema, or domain version semantics were changed.

## Infrastructure milestone: Native iOS Distribution Packaging

- Created `DryFireVision.xcodeproj` for the production native Swift/SwiftUI iOS application.
- Created application target `DryFireVision` and shared scheme `DryFireVision`.
- The target uses `DryFireVision/App/DryFireVisionApp.swift` as the only `@main` app entry point.
- The Xcode project uses Xcode 16 file-system synchronized groups so the existing native Swift source tree is the app target source root without duplicating or relocating production code.
- Deployment target is iOS 17.0, matching the Swift package platform decision.
- Bundle identifier is centralized as `PRODUCT_BUNDLE_IDENTIFIER = $(DFV_BUNDLE_IDENTIFIER)`; the approved value to supply in CI is `com.clarkiioutdoors.dryfirevision`.
- Application versions are configured with `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 1`; domain analysis/configuration/schema versions were not changed.
- Info.plist is generated from build settings with camera and microphone usage descriptions only.
- Created `DryFireVision/Resources/Assets.xcassets` and `AppIcon.appiconset` with a temporary development icon; final AppIcon artwork remains a release prerequisite.
- No special app entitlements are currently required or configured for camera, microphone, AVFoundation, Vision, SwiftData, or local file storage.
- Signing is prepared for CI-supplied manual signing values using `APPLE_TEAM_ID`, `DFV_PROVISIONING_PROFILE_SPECIFIER`, and externally supplied certificates/profiles/secrets.
- `Package.swift` remains in place for deterministic package-oriented tests. The app target directly compiles the production SwiftUI/source tree through the Xcode project to avoid a packaging-driven architecture rewrite.
- Created `docs/IOS_CI_BUILD.md` with project path, scheme, target, deployment target, Info.plist strategy, asset catalog status, signing expectations, and the macOS archive command.
- Updated `.gitignore` to exclude archives, IPA exports, provisioning profiles, signing certificates, App Store Connect private keys, and local secret config files.

Checks run in the Windows environment:

- Read Document 07 engineering guidelines, current `BUILD_STATUS.md`, `Package.swift`, and the native SwiftUI source tree.
- Confirmed `AGENTS.md` is not present.
- Searched production and test source for `@main`, AVFoundation, Vision, SwiftData, camera/microphone permission usage, and speculative entitlement requirements.
- Confirmed there is a single production `@main` entry point.
- Confirmed test sources remain under `Tests/` and are not part of the app target's synchronized production source root.
- Parsed the shared scheme as XML and the asset catalog metadata as JSON.
- Confirmed `swift` and `xcodebuild` are not available in the current Windows environment, so Swift tests and Xcode archive validation could not be run locally.

Checks requiring macOS/Xcode:

- `xcodebuild archive` for `DryFireVision.xcodeproj` / scheme `DryFireVision`.
- Xcode 16-or-newer project loading for the file-system synchronized app target.
- iOS compilation and linking of SwiftUI, AVFoundation, Vision, and SwiftData code.
- Code signing, provisioning, archive export, App Store Connect upload, and TestFlight install validation.

Unresolved distribution prerequisites:

- CI signing assets and secret values must be configured outside the repository.
- Final App Store-ready AppIcon artwork must replace the temporary development icon before release.
- Native iPhone/TestFlight smoke validation remains required.

No Dry Fire product behavior, Live Fire behavior, analysis algorithms, UX flows, persistence schema, or domain version semantics were changed.

## Previous milestone

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
