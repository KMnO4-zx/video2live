# Video2Live Latest Device Validation Record

Generated: 2026-06-17 16:18 CST

This record is prefilled from the latest passing packaged Photos smoke log:

```text
/tmp/video2live-iteration36-photos-smoke.log
```

Use it to complete the remaining real-device checks on an iPhone using the same Apple ID and iCloud Photos library as this Mac.

## Mac-Side Proven Assets

| Cover mode | Photos local identifier | Photos ID | Live Photo asset identifier | MOV duration | Codec | Album | Mac Live Photo | PhotoKit reload | Resource pair | iCloud round trip | Validation record history |
|---|---|---|---|---:|---|---|---|---|---|---|---:|
| Video frame | `01900001-4C41-443B-9FCB-5461C37D79FD/L0/001` | `01900001-4C41-443B-9FCB-5461C37D79FD` | `264825AA-C1F8-40D1-A105-56B147B471ED` | 3.000s | hvc1 | Video2Live | pass | pass | photo + pairedVideo | pass | 1 |
| Uploaded cover | `295C0620-B92D-4A0C-8F3D-83BF4F780758/L0/001` | `295C0620-B92D-4A0C-8F3D-83BF4F780758` | `48858DF9-9854-46D7-A3DB-8ECEDF31942E` | 3.000s | hvc1 | Video2Live | pass | pass | photo + pairedVideo | pass | 2 |

## iCloud Tracking

```text
Video-frame cloud identifier:
01900001-4C41-443B-9FCB-5461C37D79FD:001:Ad3nk3i62ePILkFwuKkJJ8V1JfQr

Uploaded-cover cloud identifier:
295C0620-B92D-4A0C-8F3D-83BF4F780758:001:AX47HBBg1WUjmcDhRwcsAPY+2H23
```

## Current Device Availability

```text
xcrun devicectl list devices
No devices found.
```

No connected iPhone was available from this Mac session. The checks below still need to be completed on a real iPhone.

## iPhone Photos Checks

| Check | Video frame | Uploaded cover | Notes |
|---|---|---|---|
| Appears in iPhone Photos > Albums > Video2Live | pass/fail | pass/fail | |
| Opens with Live badge | pass/fail | pass/fail | |
| Long-press playback animates | pass/fail | pass/fail | |
| Cover/key photo matches intended frame/image | pass/fail | pass/fail | |

## WeChat Moments Checks

| Check | Video frame | Uploaded cover | Notes |
|---|---|---|---|
| Selectable from iPhone Photos | pass/fail | pass/fail | |
| Preview/publish flow accepts the item | pass/fail | pass/fail | |
| Published/test-visible post preserves expected motion behavior | pass/fail | pass/fail | |

## Xiaohongshu Checks

| Check | Video frame | Uploaded cover | Notes |
|---|---|---|---|
| Selectable from iPhone Photos | pass/fail | pass/fail | |
| Publish/draft flow accepts the item | pass/fail | pass/fail | |
| Posted/draft item preserves expected motion behavior | pass/fail | pass/fail | |

## Completion Gate

Only mark the objective complete after all iPhone Photos, WeChat Moments, and Xiaohongshu rows above are recorded as pass for both cover modes.
