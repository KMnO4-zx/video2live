# Video2Live iPhone Publish Validation

This checklist covers the parts of the objective that cannot be proven by the Mac command line alone: iCloud Photos sync, iPhone playback, and posting through WeChat Moments / Xiaohongshu.

## Mac Evidence Before Device Testing

Run these commands from the repository root:

```sh
cd src
swift build
swift test
swift run Video2LiveSmoke
./build_app.sh
cd ..
codesign --verify --deep --strict --verbose=2 src/.build/release/Video2Live.app
plutil -p src/.build/release/Video2Live.app/Contents/Info.plist
open -W -n src/.build/release/Video2Live.app --args \
  --smoke-app-workflow \
  --input "$PWD/videos/lulu.mp4" \
  --smoke-log /tmp/video2live-app-workflow-smoke.log
cat /tmp/video2live-app-workflow-smoke.log
open -W -n src/.build/release/Video2Live.app --args \
  --smoke-save-to-photos \
  --input "$PWD/videos/lulu.mp4" \
  --smoke-log /tmp/video2live-photos-smoke.log
cat /tmp/video2live-photos-smoke.log
```

Mac-side pass criteria:

- `swift build` completes with no errors or warnings.
- Xcode 26.5 SDK is active, and `src/Sources/Video2Live/LiquidGlass.swift` compiles SwiftUI's macOS 26 `glassEffect`, `GlassEffectContainer`, `.glass`, and `.glassProminent` APIs behind availability checks.
- `swift test` passes all core tests.
- `Video2LiveSmoke` prints `SMOKE_OK`.
- `build_app.sh` completes and signs `Video2Live.app`.
- `codesign` reports the app is valid on disk and satisfies its designated requirement.
- The packaged `Info.plist` includes `CFBundleDisplayName=Video2Live`, `NSPhotoLibraryUsageDescription`, and `NSPhotoLibraryAddUsageDescription`; both Photos descriptions mention saving generated Live Photos to the `Video2Live` album.
- The app output panel shows the current `照片权限` state, and when Photos access is denied or restricted the `打开照片权限设置` button opens the recovery path.
- If Photos permission is denied after rebuilding the ad-hoc signed app, use `打开照片权限设置`, allow `Video2Live` in System Settings > Privacy & Security > Photos, or reset only this app's grant with `tccutil reset Photos com.video2live.mac` and rerun the app to approve the prompt.
- The app disables generation unless the selected clip is between 1 and 5 seconds.
- App workflow smoke prints `APP_WORKFLOW_SMOKE_OK`.
- App workflow smoke logs `APP_WORKFLOW_SMOKE_IMPORTED`, `APP_WORKFLOW_SMOKE_TRIM`, `APP_WORKFLOW_SMOKE_PLAYBACK_BOUNDED`, both `videoFrame` and `uploadedCover` outputs, and `previewPlaybackRequest` greater than zero.
- Packaged-app Photos smoke prints `APP_PHOTOS_SMOKE_OK`.
- Both `videoFrame.photosIsLivePhoto=true` and `uploadedCover.photosIsLivePhoto=true` appear in `/tmp/video2live-photos-smoke.log`.
- Both `videoFrame.photosCanLoadLivePhoto=true` and `uploadedCover.photosCanLoadLivePhoto=true` appear in `/tmp/video2live-photos-smoke.log`.
- Both `videoFrame.photosHasLivePhotoResourcePair=true` and `uploadedCover.photosHasLivePhotoResourcePair=true` appear in `/tmp/video2live-photos-smoke.log`.
- Both cover modes include `photo` and `pairedVideo` in `photosResourceTypes` in `/tmp/video2live-photos-smoke.log`.
- Both `videoFrame.photosIsInAlbum=true` and `uploadedCover.photosIsInAlbum=true` appear in `/tmp/video2live-photos-smoke.log`.
- Both cover modes report `photosAlbumTitle=Video2Live` in `/tmp/video2live-photos-smoke.log`.
- Both cover modes log `photosHasCloudIdentifier`, `photosCloudIdentifier`, and `photosCloudIdentifierRoundTripMatches`; `photosHasCloudIdentifier=true` plus `photosCloudIdentifierRoundTripMatches=true` is a Mac-side iCloud Photos tracking signal when iCloud can provide it, but iPhone playback still requires manual device validation.
- For both cover modes, `photoSize` and `videoSize` match in `/tmp/video2live-photos-smoke.log`.
- For both cover modes, `photoIdentifierMatches=true`, `videoIdentifierMatches=true`, and `hasTimedMetadataTrack=true` appear in `/tmp/video2live-photos-smoke.log`.
- For both cover modes, `videoCodec` is `hvc1`, `hev1`, or `avc1`, and `isSupportedVideoCodec=true` appears in `/tmp/video2live-photos-smoke.log`.
- For both cover modes, `videoDurationSeconds` is between `1.000` and `5.000`, and `isDurationCompatible=true` appears in `/tmp/video2live-photos-smoke.log`.
- For both cover modes, `validationRecordHasResourcePairField=true`, `validationRecordHasDurationField=true`, `validationRecordHasCloudIdentifierField=true`, `validationRecordHasCloudRoundTripField=true`, `validationRecordHasAlbumFields=true`, `validationRecordHasIPhoneFields=true`, `validationRecordHasWeChatFields=true`, and `validationRecordHasXiaohongshuFields=true` appear in `/tmp/video2live-photos-smoke.log`.
- After saving through the app UI, the output panel shows a short Photos ID and the `复制 Photos ID` button copies it for matching Mac/iPhone/social validation records.

Portrait-video regression check:

```sh
ffmpeg -y \
  -f lavfi -i testsrc2=size=1080x1920:rate=30:duration=4 \
  -f lavfi -i sine=frequency=440:duration=4 \
  -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac \
  /tmp/video2live-portrait.mp4

cd src
swift run Video2LiveSmoke /tmp/video2live-portrait.mp4
cd ..
open -W -n src/.build/release/Video2Live.app --args \
  --smoke-save-to-photos \
  --input /tmp/video2live-portrait.mp4 \
  --smoke-log /tmp/video2live-portrait-photos-smoke.log
cat /tmp/video2live-portrait-photos-smoke.log
```

Portrait pass criteria:

- Both cover modes report `photoSize=1080x1920`, `videoSize=1080x1920`, and `livePhotoSize=1080x1920`.
- Both cover modes report `photoIdentifierMatches=true`, `videoIdentifierMatches=true`, and `hasTimedMetadataTrack=true`.
- Both cover modes report `isSupportedVideoCodec=true`.
- Both cover modes report `photosIsLivePhoto=true`.

Rotated-display-matrix regression check:

```sh
ffmpeg -y \
  -f lavfi -i testsrc2=size=1920x1080:rate=30:duration=4 \
  -f lavfi -i sine=frequency=660:duration=4 \
  -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac \
  /tmp/video2live-rotated-base.mp4

ffmpeg -y -display_rotation 90 \
  -i /tmp/video2live-rotated-base.mp4 \
  -c copy /tmp/video2live-rotated.mp4

ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height:stream_side_data=rotation \
  -of default=noprint_wrappers=1 \
  /tmp/video2live-rotated.mp4

cd src
swift run Video2LiveSmoke /tmp/video2live-rotated.mp4
cd ..
open -W -n src/.build/release/Video2Live.app --args \
  --smoke-save-to-photos \
  --input /tmp/video2live-rotated.mp4 \
  --smoke-log /tmp/video2live-rotated-photos-smoke.log
cat /tmp/video2live-rotated-photos-smoke.log
```

Rotated-display-matrix pass criteria:

- `ffprobe` reports `width=1920`, `height=1080`, and `rotation=90`.
- Both cover modes report `photoSize=1080x1920`, `videoSize=1080x1920`, and `livePhotoSize=1080x1920`.
- Both cover modes report `photoIdentifierMatches=true`, `videoIdentifierMatches=true`, and `hasTimedMetadataTrack=true`.
- Both cover modes report `isSupportedVideoCodec=true`.
- Both cover modes report `photosIsLivePhoto=true`.

## Manual iPhone / iCloud Validation

Prerequisites:

- The Mac and iPhone use the same Apple ID for iCloud Photos.
- iCloud Photos is enabled on both devices.
- The iPhone has WeChat and Xiaohongshu installed and logged in.
- Keep the latest Mac smoke log open so the saved Photos ID and Live Photo mode can be matched in the `Video2Live` album.
- Use `src/latest_device_validation_record.md` for the latest prefilled Mac-side Photos IDs and iCloud tracking values.

Steps:

1. Open `src/.build/release/Video2Live.app`.
2. Import a real `.mp4` or `.mov` video.
3. Select a 1-5 second range using the range timeline.
4. Generate once with `视频选帧`, save to Photos, confirm the app shows `Live Photo 已验证`, and click `复制验证记录`.
5. Generate once with `上传图片`, adjust the crop box, save to Photos, confirm the app shows `Live Photo 已验证`, and click `复制验证记录`.
6. Click `复制全部验证记录` so both cover-mode records are available for device/social validation.
7. Click `打开 Photos`, open the `Video2Live` album, and confirm the latest two items animate as Live Photos in macOS Photos.
8. Wait for iCloud Photos to sync to iPhone.
9. On iPhone Photos, open Albums > `Video2Live`, then open the latest two synced items and long-press each one.
10. Pass if both items animate and remain marked as Live Photos on iPhone.

Record:

```text
Mac save time:
Video-frame Photos ID:
Uploaded-cover Photos ID:
Video-frame MOV duration:
Uploaded-cover MOV duration:
Video-frame cloud identifier:
Uploaded-cover cloud identifier:
Video-frame cloud round-trip matches: yes/no
Uploaded-cover cloud round-trip matches: yes/no
Video-frame found in iPhone Video2Live album: yes/no
Uploaded-cover found in iPhone Video2Live album: yes/no
Video-frame item appeared on iPhone: yes/no
Uploaded-cover item appeared on iPhone: yes/no
Video-frame iPhone Live Photo playback: pass/fail
Uploaded-cover iPhone Live Photo playback: pass/fail
Notes:
```

## WeChat Moments Validation

Steps:

1. On iPhone, open WeChat.
2. Start a Moments post.
3. Pick the synced `视频选帧` Live Photo from Photos.
4. Confirm WeChat accepts the item and shows motion preview if available.
5. Publish privately or to a limited test audience.
6. Repeat with the `上传图片` Live Photo.

Pass criteria:

- WeChat can select both items from Photos.
- The post succeeds without converting selection into an unsupported still-only item before publish.
- The published/test-visible post displays expected motion behavior for both cover modes.

Record:

```text
Video-frame WeChat selection: pass/fail
Video-frame WeChat publish: pass/fail
Video-frame Photos ID:
Uploaded-cover WeChat selection: pass/fail
Uploaded-cover WeChat publish: pass/fail
Uploaded-cover Photos ID:
Notes:
```

## Xiaohongshu Validation

Steps:

1. On iPhone, open Xiaohongshu.
2. Create a new post.
3. Pick the synced `视频选帧` Live Photo from Photos.
4. Confirm Xiaohongshu accepts the item and retains motion/live behavior if supported by the current app version.
5. Publish as a private/draft/test post where possible.
6. Repeat with the `上传图片` Live Photo.

Pass criteria:

- Xiaohongshu can select both items from Photos.
- The post flow completes without upload/import errors.
- The posted or draft item preserves the intended motion behavior according to Xiaohongshu's current Live Photo handling.

Record:

```text
Video-frame Xiaohongshu selection: pass/fail
Video-frame Xiaohongshu publish/draft: pass/fail
Video-frame Photos ID:
Uploaded-cover Xiaohongshu selection: pass/fail
Uploaded-cover Xiaohongshu publish/draft: pass/fail
Uploaded-cover Photos ID:
Notes:
```

## Failure Triage

- If the Mac smoke passes but iPhone does not show the item, check iCloud Photos sync status on both devices.
- If the item appears on iPhone but does not animate, confirm it still has the Live badge in iPhone Photos.
- If Photos playback works but WeChat or Xiaohongshu fails, the issue is likely app-specific import behavior rather than Live Photo generation.
- If only the uploaded-cover item fails, rerun with a simpler same-aspect cover image and inspect the crop box selection.
- If both social apps convert to still images, capture the app version and iOS version before changing generation logic.

## Completion Gate

After filling `src/latest_device_validation_record.md` with real iPhone, WeChat, and Xiaohongshu results, run:

```sh
src/verify_device_validation_record.sh src/latest_device_validation_record.md
```

Pass only when it prints `DEVICE_VALIDATION_COMPLETE`.

## Xiaomi 17 Pro / Xiaohongshu Android Path

The user clarified that the practical target phone is Xiaomi 17 Pro. For that path, use:

```text
src/latest_xiaomi_xhs_validation_record.md
```

After filling the Xiaomi Gallery and Xiaohongshu Android rows with real device results, run:

```sh
src/verify_xiaomi_xhs_validation.sh src/latest_xiaomi_xhs_validation_record.md
```

Pass only when it prints `XIAOMI_XHS_VALIDATION_COMPLETE`.
