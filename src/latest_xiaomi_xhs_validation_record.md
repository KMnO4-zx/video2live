# Video2Live Xiaomi 17 Pro / Xiaohongshu Validation Record

Generated: 2026-06-17 18:38 CST

This record is prefilled from the latest passing Xiaomi/Xiaohongshu export smoke log:

```text
/tmp/video2live-iteration45-xiaomi-xhs-smoke.log
```

Target phone: Xiaomi 17 Pro

## Mac-Side Exported Assets

| Cover mode | Motion Photo candidate | Fallback MP4 | Cover JPG | MP4 codec | MP4 duration | XMP | MicroVideo offset | Appended MP4 |
|---|---|---|---|---|---:|---|---|---|
| Video frame | `/var/folders/16/6n95sj851p3c54bf8vtdd8b80000gn/T/Video2Live/XiaomiXHSSmoke-videoFrame-AA0C6DEB-F7BF-40F2-81D8-CA9D7D42DDF8/xiaomi-xhs-live-photo.jpg` | `/var/folders/16/6n95sj851p3c54bf8vtdd8b80000gn/T/Video2Live/XiaomiXHSSmoke-videoFrame-AA0C6DEB-F7BF-40F2-81D8-CA9D7D42DDF8/_debug/fallback-video.mp4` | `/var/folders/16/6n95sj851p3c54bf8vtdd8b80000gn/T/Video2Live/XiaomiXHSSmoke-videoFrame-AA0C6DEB-F7BF-40F2-81D8-CA9D7D42DDF8/_debug/cover.jpg` | avc1 | 3.002s | pass | pass | pass |
| Uploaded cover | `/var/folders/16/6n95sj851p3c54bf8vtdd8b80000gn/T/Video2Live/XiaomiXHSSmoke-uploadedCover-D554FE1B-EF26-4AD4-B07B-749D54FFF142/xiaomi-xhs-live-photo.jpg` | `/var/folders/16/6n95sj851p3c54bf8vtdd8b80000gn/T/Video2Live/XiaomiXHSSmoke-uploadedCover-D554FE1B-EF26-4AD4-B07B-749D54FFF142/_debug/fallback-video.mp4` | `/var/folders/16/6n95sj851p3c54bf8vtdd8b80000gn/T/Video2Live/XiaomiXHSSmoke-uploadedCover-D554FE1B-EF26-4AD4-B07B-749D54FFF142/_debug/cover.jpg` | avc1 | 3.002s | pass | pass | pass |

## Transfer Steps

1. Use the app's `导出候选动态图 JPG` button, choose the target export folder in the system dialog, or transfer the smoke JPG above for immediate testing.
2. Copy only the top-level `xiaomi-xhs-live-photo.jpg` to Xiaomi 17 Pro first.
3. In Xiaomi Gallery, test `xiaomi-xhs-live-photo.jpg` first.
4. In Xiaohongshu Android, create a post and select `xiaomi-xhs-live-photo.jpg` from the phone gallery.
5. Use `_debug/fallback-video.mp4` only as a diagnostic fallback if the Motion Photo candidate is not recognized as a live image.

## Xiaomi Gallery Checks

| Check | Video frame | Uploaded cover | Notes |
|---|---|---|---|
| Motion Photo candidate appears in Xiaomi Gallery | pass/fail | pass/fail | |
| Xiaomi Gallery recognizes it as dynamic/live photo | pass/fail | pass/fail | |
| Long-press or motion playback animates | pass/fail | pass/fail | |
| Cover/key photo matches intended frame/image | pass/fail | pass/fail | |

## Xiaohongshu Android Checks

| Check | Video frame | Uploaded cover | Notes |
|---|---|---|---|
| Motion Photo candidate selectable from Xiaomi Gallery | pass/fail | pass/fail | |
| Xiaohongshu import shows live/dynamic-photo behavior before publish | pass/fail | pass/fail | |
| Published/draft item preserves live/dynamic-photo behavior | pass/fail | pass/fail | |

## Fallback MP4 Diagnostic

| Check | Video frame | Uploaded cover | Notes |
|---|---|---|---|
| Fallback MP4 selectable in Xiaohongshu | pass/fail | pass/fail | This proves posting a short video is possible, but does not satisfy the live image target by itself. |

## Completion Gate

Only mark the Xiaomi/Xiaohongshu target complete after every Xiaomi Gallery and Xiaohongshu Android row above is recorded as `pass | pass`.
