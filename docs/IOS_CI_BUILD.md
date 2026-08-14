# iOS CI Build

Dry Fire Vision remains a native Swift/SwiftUI iOS app with Windows + VS Code + Codex as the primary source-editing workflow. Apple-only compilation, signing, archive creation, App Store Connect upload, and TestFlight validation must run on a macOS/Xcode environment such as GitHub Actions macOS runners.

## Xcode packaging

- Xcode project: `DryFireVision.xcodeproj`
- Application target: `DryFireVision`
- Shared scheme: `DryFireVision`
- Xcode requirement: Xcode 16 or newer, because the project uses a file-system synchronized source root for the existing native Swift tree.
- Deployment target: iOS 17.0
- Build configurations: `Debug`, `Release`
- App entry point: `DryFireVision/App/DryFireVisionApp.swift`
- Package manifest retained: `Package.swift`

## Bundle identifier

The approved production bundle identifier is:

```text
com.clarkiioutdoors.dryfirevision
```

The Xcode target centralizes this in `PRODUCT_BUNDLE_IDENTIFIER = $(DFV_BUNDLE_IDENTIFIER)` for both Debug and Release configurations. Configure the GitHub secret `DFV_BUNDLE_IDENTIFIER` with the approved value above.

## Info.plist strategy

The app uses generated Info.plist build settings (`GENERATE_INFOPLIST_FILE = YES`) rather than a checked-in plist.

Configured usage descriptions:

- `NSCameraUsageDescription`: Dry Fire Vision uses the camera to detect body pose and analyze visible movement during training.
- `NSMicrophoneUsageDescription`: Dry Fire Vision uses the microphone only in Live Fire Beta to detect training audio events after you choose that mode.

No unrelated permissions are configured.

## Assets

Asset catalog:

```text
DryFireVision/Resources/Assets.xcassets
```

App icon set:

```text
DryFireVision/Resources/Assets.xcassets/AppIcon.appiconset
```

The catalog structure is present and includes `DevelopmentAppIcon-1024.png`, a temporary development icon so asset compilation has a real 1024px source image. Final App Store-ready AppIcon artwork is still a release prerequisite. Do not treat the temporary icon as approved brand artwork.

## Entitlements

No app entitlements file is currently required or configured. The implemented app uses ordinary camera, microphone, AVFoundation, Vision, SwiftData, and local file storage capabilities, which do not require special entitlements.

Do not add CloudKit, iCloud, Push Notifications, HealthKit, Sign in with Apple, App Groups, or other capabilities unless approved product scope and implemented code require them.

## Signing

The target uses manual signing placeholders intended for CI-supplied values:

```text
DEVELOPMENT_TEAM = $(APPLE_TEAM_ID)
PROVISIONING_PROFILE_SPECIFIER = $(DFV_PROVISIONING_PROFILE_SPECIFIER)
CODE_SIGN_STYLE = Manual
```

Do not commit certificates, provisioning profiles, App Store Connect API private keys, or other secrets.

## Expected archive command

The macOS runner should archive with values supplied by repository/environment secrets:

```sh
xcodebuild \
  -project DryFireVision.xcodeproj \
  -scheme DryFireVision \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/DryFireVision.xcarchive" \
  DFV_BUNDLE_IDENTIFIER="$DFV_BUNDLE_IDENTIFIER" \
  APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  DFV_PROVISIONING_PROFILE_SPECIFIER="$DFV_PROVISIONING_PROFILE_SPECIFIER" \
  CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" \
  archive
```

This command must be validated on macOS with Xcode. It cannot be validated from Windows.

## GitHub Actions workflow

Workflow file:

```text
.github/workflows/ios-testflight.yml
```

Runner image:

```text
macos-15
```

The workflow lists available Xcode installations and selects the newest available stable Xcode installation on the runner instead of hard-coding an obsolete Xcode path.

Normal handoff:

```text
Windows + VS Code + Codex
-> git push
-> GitHub
-> GitHub Actions macOS runner
-> Xcode archive
-> IPA
-> optional TestFlight upload
```

Triggers:

- `workflow_dispatch` with `upload_to_testflight` boolean input, default `false`.
- `push` to `main` for build validation only.

Build-only mode:

- Run the workflow manually with `upload_to_testflight = false`, or push to `main`.
- The workflow checks out the repository, selects Xcode, prints bounded diagnostics, validates the project/scheme/resources/secrets, installs CI signing assets, optionally runs `swift test`, archives, exports a signed IPA, and uploads build artifacts.
- It does not upload to App Store Connect.

Build + TestFlight mode:

- Run the workflow manually with `upload_to_testflight = true`.
- After archive/export/artifact upload, the workflow writes the App Store Connect API private key to the runner's standard temporary Apple key location as `AuthKey_<KEY_ID>.p8`.
- It uploads the signed IPA using `xcrun altool --upload-app` with App Store Connect API key authentication.
- It uploads the binary only. It does not submit App Review, release publicly, enable external testing, or change App Store metadata.

Artifact:

```text
DryFireVision-iOS-${{ github.run_number }}
```

The artifact includes the exported IPA and build logs. The IPA is exported to:

```text
build/export/
```

Troubleshooting:

- Read the GitHub Actions step logs first, especially `xcodebuild -list`, `swift test`, `xcodebuild archive`, `xcodebuild -exportArchive`, and `xcrun altool`.
- The workflow intentionally preserves real compiler/signing/export errors instead of hiding them behind custom scripts.

## GitHub secrets checklist

- [ ] `DFV_BUNDLE_IDENTIFIER`
- [ ] `APPLE_TEAM_ID`
- [ ] `BUILD_CERTIFICATE_BASE64`
- [ ] `P12_PASSWORD`
- [ ] `BUILD_PROVISION_PROFILE_BASE64`
- [ ] `DFV_PROVISIONING_PROFILE_SPECIFIER`
- [ ] `KEYCHAIN_PASSWORD`
- [ ] `APPSTORE_API_KEY_ID`
- [ ] `APPSTORE_ISSUER_ID`
- [ ] `APPSTORE_API_PRIVATE_KEY`

Do not store sample real secrets in the repository.

## Workflow signing and export details

Signing certificate installation:

- Decodes `BUILD_CERTIFICATE_BASE64` to a temporary `.p12`.
- Creates and unlocks a temporary runner keychain using `KEYCHAIN_PASSWORD`.
- Imports the `.p12` using `P12_PASSWORD`.
- Grants `codesign`/Xcode access through the temporary keychain.
- Deletes the temporary keychain and certificate copy in an `always()` cleanup step.

Provisioning profile installation:

- Decodes `BUILD_PROVISION_PROFILE_BASE64` to a temporary `.mobileprovision`.
- Decodes it with `security cms -D`.
- Reads the profile UUID, name, application identifier, and team identifier.
- Verifies the profile matches `DFV_BUNDLE_IDENTIFIER`, `APPLE_TEAM_ID`, and `DFV_PROVISIONING_PROFILE_SPECIFIER`.
- Installs it as `~/Library/MobileDevice/Provisioning Profiles/<UUID>.mobileprovision`.

ExportOptions strategy:

- The workflow dynamically generates a CI-only `ExportOptions.plist` in the runner temp directory.
- Export method is `app-store-connect`, matching current Xcode App Store Connect export semantics.
- Manual signing maps `DFV_BUNDLE_IDENTIFIER` to `DFV_PROVISIONING_PROFILE_SPECIFIER`.
- No private credentials are embedded in the plist.

## Windows vs macOS validation

Possible from Windows + VS Code + Codex:

- Source and project-file inspection.
- Documentation updates.
- Git operations.
- Static checks that referenced files, scheme, resources, and package manifest exist.
- XML/JSON syntax checks for the shared scheme and asset catalog metadata.
- Swift package tests only if a compatible Swift toolchain is installed.

Requires macOS/Xcode or TestFlight:

- `xcodebuild archive`.
- iOS compilation and linking.
- Code signing and provisioning.
- App Store Connect upload.
- TestFlight install and physical-device validation.
- AVFoundation, Vision, SwiftData, microphone, permissions, performance, and thermal smoke tests.
