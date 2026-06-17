# Video2Live Completion Audit

Audit time: 2026-06-17 16:22 CST

This file tracks the objective item by item. It separates Mac-side evidence from requirements that still need real iPhone / social-app validation.

## Current Status

Not complete yet. The macOS app, Live Photo generation, Photos save, iCloud identifier tracking, Xiaomi/Xiaohongshu Android export, and Liquid Glass UI are implemented and smoke-tested. The user clarified the practical target device is Xiaomi 17 Pro; the remaining unproven requirement is real Xiaomi Gallery recognition and Xiaohongshu Android live/dynamic-photo posting behavior.

Current device check:

```text
xcrun devicectl list devices
No devices found.
```

No connected iPhone was available for device-side validation during this audit.

Latest asset identifiers and device-side result fields are prefilled in `src/latest_device_validation_record.md`.
Latest Xiaomi 17 Pro / Xiaohongshu Android result fields are prefilled in `src/latest_xiaomi_xhs_validation_record.md`.

Current device-validation gate:

```text
src/verify_device_validation_record.sh src/latest_device_validation_record.md
DEVICE_VALIDATION_INCOMPLETE
```

## Requirement Matrix

| # | Requirement | Current evidence | Status |
|---|---|---|---|
| 1 | Import video and preview playback in the app | `ContentView` uses file picker and drag/drop. `AppViewModel` stages video files and assigns an `AVPlayerItem`. Packaged app workflow smoke logs `APP_WORKFLOW_SMOKE_IMPORTED` and `APP_WORKFLOW_SMOKE_PLAYBACK_BOUNDED`. | Proven on Mac |
| 2 | Select a 1-5 second clip with a timeline and show duration | `RangeTimelineSlider` drives `startTime` / `endTime`; generation is gated by `isSelectedDurationCompatible`. Workflow smoke selects a 5.0s range and generated MOV validates to 4.955s after export rounding control. | Proven on Mac |
| 3 | Cover from video frame and uploaded image with crop/scale | `CoverMode.videoFrame` and `CoverMode.uploadedImage` are both implemented. Core tests cover crop aspect locking and output pixels. Workflow and Photos smokes generate both cover modes. | Proven on Mac |
| 4 | Generate a Live Photo recognized by macOS Photos | `LivePhotoBuilder` writes paired JPEG/MOV identifiers and timed metadata. Photos smoke reports `photosIsLivePhoto=true`, `photosCanLoadLivePhoto=true`, `photosHasLivePhotoResourcePair=true` for both cover modes. | Proven on Mac Photos |
| 5 | iCloud sync to iPhone and iPhone playback | Photos smoke reports `photosHasCloudIdentifier=true` and `photosCloudIdentifierRoundTripMatches=true`, proving Mac-side PhotoKit cloud tracking. The app keeps a session history of device/social validation records so both cover modes can be checked on the iPhone. Real iPhone playback still requires a connected/synced iPhone and manual validation. | Not proven |
| 5a | Xiaomi 17 Pro / Xiaohongshu Android live image posting | Xiaomi/XHS smoke exports an Android Motion Photo candidate JPEG plus H.264 MP4 fallback for both cover modes. It verifies XMP metadata, Motion Photo flags, MicroVideo offset, container video length, appended MP4 bytes, codec, and duration. Real Xiaomi Gallery recognition and Xiaohongshu Android live/dynamic-photo posting still require manual device validation. | Not proven |
| 6 | macOS 26 Liquid Glass UI | `LiquidGlass.swift` uses `glassEffect`, `GlassEffectContainer`, `.glass`, and `.glassProminent` behind macOS 26 availability checks, with fallback material styling, hover, press, and spring animation. | Proven by code/build |
| 7 | Build succeeds, app runs without crashes or console errors | `swift build`, `swift test`, `swift run Video2LiveSmoke`, `./build_app.sh`, `codesign --verify`, packaged app workflow smoke, and packaged Photos smoke all passed through Iteration 37. | Proven for tested Mac flows |

## Latest Mac Validation Evidence

Commands run through Iteration 37:

```sh
cd src
swift build
swift test
swift run Video2LiveSmoke
./build_app.sh
cd ..
codesign --verify --deep --strict --verbose=2 src/.build/release/Video2Live.app
src/.build/release/Video2Live.app/Contents/MacOS/Video2Live \
  --smoke-app-workflow \
  --input "$PWD/videos/lulu.mp4" \
  --smoke-log /tmp/video2live-iteration36-app-workflow-smoke.log
open -W -n src/.build/release/Video2Live.app --args \
  --smoke-save-to-photos \
  --input /tmp/video2live-smoke-lulu.mp4 \
  --smoke-log /tmp/video2live-iteration36-photos-smoke.log
```

Important latest Photos-smoke results:

```text
APP_PHOTOS_SMOKE_OK
videoFrame.photosLocalIdentifier=01900001-4C41-443B-9FCB-5461C37D79FD/L0/001
videoFrame.videoDurationSeconds=3.000
videoFrame.photosIsLivePhoto=true
videoFrame.photosCanLoadLivePhoto=true
videoFrame.photosHasLivePhotoResourcePair=true
videoFrame.photosIsInAlbum=true
videoFrame.photosHasCloudIdentifier=true
videoFrame.photosCloudIdentifierRoundTripMatches=true
videoFrame.validationRecordHistoryCount=1
uploadedCover.photosLocalIdentifier=295C0620-B92D-4A0C-8F3D-83BF4F780758/L0/001
uploadedCover.videoDurationSeconds=3.000
uploadedCover.photosIsLivePhoto=true
uploadedCover.photosCanLoadLivePhoto=true
uploadedCover.photosHasLivePhotoResourcePair=true
uploadedCover.photosIsInAlbum=true
uploadedCover.photosHasCloudIdentifier=true
uploadedCover.photosCloudIdentifierRoundTripMatches=true
uploadedCover.validationRecordHistoryCount=2
```

## Remaining Proof Required

To complete the objective, run the checklist in `src/iphone_publish_validation.md` with a real iPhone that uses the same Apple ID and iCloud Photos account as the Mac:

1. Confirm both saved items appear in the iPhone `Video2Live` album.
2. Confirm both saved items animate as Live Photos in iPhone Photos.
3. Confirm WeChat Moments can select and publish both items without losing the intended motion behavior.
4. Confirm Xiaohongshu can select and publish or draft both items without import/upload errors and with expected motion handling.

After those four checks are recorded, the objective can be marked complete.

The local completion gate for the manually filled device record is:

```sh
src/verify_device_validation_record.sh src/latest_device_validation_record.md
```

It must print `DEVICE_VALIDATION_COMPLETE` before the objective can be marked complete.

The local completion gate for the manually filled Xiaomi 17 Pro / Xiaohongshu record is:

```sh
src/verify_xiaomi_xhs_validation.sh src/latest_xiaomi_xhs_validation_record.md
```

It must print `XIAOMI_XHS_VALIDATION_COMPLETE` before the Xiaomi/Xiaohongshu target can be marked complete.

Latest packaged Xiaomi/Xiaohongshu smoke evidence:

```text
APP_XIAOMI_XHS_SMOKE_OK
videoFrame.hasXMPMetadata=true
videoFrame.hasMotionPhotoFlag=true
videoFrame.microVideoOffsetMatchesVideoLength=true
videoFrame.containerItemLengthMatchesVideoLength=true
videoFrame.appendedVideoMatchesFallbackVideo=true
videoFrame.fallbackVideoCodec=avc1
videoFrame.fallbackVideoDurationSeconds=3.002
videoFrame.isValid=true
uploadedCover.hasXMPMetadata=true
uploadedCover.hasMotionPhotoFlag=true
uploadedCover.microVideoOffsetMatchesVideoLength=true
uploadedCover.containerItemLengthMatchesVideoLength=true
uploadedCover.appendedVideoMatchesFallbackVideo=true
uploadedCover.fallbackVideoCodec=avc1
uploadedCover.fallbackVideoDurationSeconds=3.002
uploadedCover.isValid=true
```
