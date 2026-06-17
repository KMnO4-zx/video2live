# Video2Live

Video2Live is a native macOS SwiftUI app that turns a short video clip into a Live Photo resource pair and can save it to Photos.

## Build

The project lives in `src/` and builds with Swift Package Manager:

```sh
cd src
swift build
swift test
```

To create a runnable app bundle:

```sh
cd src
./build_app.sh
```

The app bundle is written to:

```text
src/.build/release/Video2Live.app
```

The bundled `Info.plist` includes Photos read/add usage descriptions that explicitly mention saving generated Live Photos into the `Video2Live` album. You can inspect the packaged metadata with:

```sh
plutil -p src/.build/release/Video2Live.app/Contents/Info.plist
```

## Current Features

- Import `.mp4` / `.mov` videos by file picker or drag and drop.
- Preview video with playback controls.
- Select a 1-5 second clip with a dual-handle range timeline; generation is disabled outside that range.
- Choose a Live Photo cover from a video frame.
- Upload a local image as the cover and crop/scale it to the video aspect ratio; same-aspect covers use the full image by default.
- Generate paired Live Photo resources.
- Preview generated output with `PHLivePhotoView`, including automatic playback and manual replay.
- Save generated resources to macOS Photos with PhotoKit.
- Verify saved Photos assets are marked as Live Photo, can be reloaded by PhotoKit as Live Photos, contain the expected `photo` + `pairedVideo` resource pair, are added to the `Video2Live` Photos album, expose a PhotoKit cloud identifier when iCloud Photos can provide one, round-trip that cloud identifier back to the same local Photos asset, show/copy the saved Photos identifier, and open Photos for iCloud/device inspection.
- Smoke-test key Live Photo metadata: JPEG/MOV asset identifiers, H.264/HEVC MOV codec, actual paired MOV duration, and timed metadata track.
- Show generated MOV codec, actual paired MOV duration, and Live Photo pairing status in the output panel before saving.
- Show the current Photos permission state in the output panel and provide an `打开照片权限设置` recovery button when macOS denies or restricts Photos access.
- Copy one device/social validation record after saving, or copy all saved records from the current session so both cover modes can be taken through iPhone / WeChat / Xiaohongshu validation together.
- Export a Xiaomi / Xiaohongshu upload JPG for Android testing: the app asks the user to choose the export location, then creates a timestamped `Video2Live-Xiaomi-XHS-*` folder containing the top-level `xiaomi-xhs-live-photo.jpg` for phone transfer; diagnostic MP4/cover files are kept under `_debug`.
- Use a custom high-contrast Liquid Glass style with translucent panels and prominent controls; native macOS 26 glass effects are intentionally not stacked on content panels because they made this tool UI hard to read.

## Notes

Full Xcode is recommended for signing, entitlement inspection, UI debugging, and device/iCloud validation, but the current app can be built with Command Line Tools.

After installing Xcode, launch it once and agree to Apple's license. Until that is done, `xcrun` may block command-line builds. `src/build_app.sh` falls back to Command Line Tools when possible.

If Photos smoke or manual saving reports that Photos permission is denied, use the app's `打开照片权限设置` button or open System Settings > Privacy & Security > Photos and allow `Video2Live`. If a local rebuild invalidates the ad-hoc signed app's TCC grant, reset only this bundle identifier and run the app again to approve the prompt:

```sh
tccutil reset Photos com.video2live.mac
```

## Validation

Run the non-mutating Live Photo generation smoke test:

```sh
cd src
swift run Video2LiveSmoke
```

Run the app workflow smoke test that exercises the real `AppViewModel` import, playback item setup, 1-5 second trimming, selected-range playback stopping, both cover modes, Live Photo generation, metadata pairing, actual paired MOV duration validation, and preview loading without writing to Photos:

```sh
# From the repository root.
open -W -n src/.build/release/Video2Live.app --args \
  --smoke-app-workflow \
  --input "$PWD/videos/lulu.mp4" \
  --smoke-log /tmp/video2live-app-workflow-smoke.log
```

Run the packaged app smoke test that goes through the app view model, saves to Photos, verifies the resulting assets are marked as Live Photo, can be reloaded by PhotoKit as Live Photos, contain the expected `photo` + `pairedVideo` resource pair, are added to the `Video2Live` Photos album, records any available PhotoKit cloud identifier, round-trips that cloud identifier back to the same local Photos asset when available, confirms the key photo / paired MOV dimensions match, checks the JPEG/MOV Live Photo metadata pair, H.264/HEVC codec, actual paired MOV duration, and validates the copied iPhone / WeChat / Xiaohongshu verification-record fields:

```sh
# From the repository root.
open -W -n src/.build/release/Video2Live.app --args \
  --smoke-save-to-photos \
  --input "$PWD/videos/lulu.mp4" \
  --smoke-log /tmp/video2live-photos-smoke.log
```

Run the Xiaomi / Xiaohongshu Android export smoke test:

```sh
# From the repository root.
src/.build/release/Video2Live.app/Contents/MacOS/Video2Live \
  --smoke-xiaomi-xhs-export \
  --input "$PWD/videos/lulu.mp4" \
  --smoke-log /tmp/video2live-xiaomi-xhs-smoke.log
```

For manual Xiaomi/Xiaohongshu testing, use only the exported top-level JPG:

```text
xiaomi-xhs-live-photo.jpg
```

Transfer that JPG to Xiaomi 17 Pro, open it in Xiaomi Gallery first, then select the same JPG in Xiaohongshu. Finder will still show it as a normal `.jpg`; the dynamic part is an embedded MP4 payload plus Motion Photo metadata. The `_debug/fallback-video.mp4` file is only a fallback for normal video posting and does not prove live-image support.

To compare against a real Xiaomi/WeChat dynamic image sample, keep the original file uncompressed and run:

```sh
src/analyze_dynamic_photo.py /path/to/real-dynamic-photo.jpg
```

The report shows whether the sample is JPEG, HEIF, GIF, or another container, whether it has Motion Photo XMP fields, and whether an MP4 payload is appended to the image file.

For iPhone playback, iCloud Photos, WeChat Moments, and Xiaohongshu validation, use:

```text
src/iphone_publish_validation.md
```

The latest Mac-side asset IDs and iCloud tracking values for real-device validation are prefilled in:

```text
src/latest_device_validation_record.md
```

For Xiaomi 17 Pro / Xiaohongshu Android validation, use:

```text
src/latest_xiaomi_xhs_validation_record.md
```

After updating that file with real Xiaomi 17 Pro / Xiaohongshu results, run:

```sh
src/verify_xiaomi_xhs_validation.sh src/latest_xiaomi_xhs_validation_record.md
```

After updating that file with real iPhone / WeChat / Xiaohongshu results, run:

```sh
src/verify_device_validation_record.sh src/latest_device_validation_record.md
```

For a requirement-by-requirement completion audit, use:

```text
src/completion_audit.md
```
