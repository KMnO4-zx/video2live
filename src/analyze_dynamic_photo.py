#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


def file_type(data: bytes) -> str:
    if data.startswith(b"\xff\xd8"):
        return "jpeg"
    if len(data) >= 12 and data[4:8] == b"ftyp":
        brands = data[8:32].decode("latin1", errors="replace")
        if any(brand in brands for brand in ("heic", "heix", "hevc", "mif1", "msf1")):
            return "heif"
        return "mp4_or_iso_bmff"
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return "gif"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    return "unknown"


def jpeg_app1_xmp_segments(data: bytes) -> list[str]:
    segments: list[str] = []
    if not data.startswith(b"\xff\xd8"):
        return segments

    offset = 2
    while offset + 4 <= len(data):
        if data[offset] != 0xFF:
            break
        marker = data[offset + 1]
        offset += 2
        if marker in (0xDA, 0xD9):
            break
        if offset + 2 > len(data):
            break
        length = int.from_bytes(data[offset:offset + 2], "big")
        if length < 2 or offset + length > len(data):
            break
        payload = data[offset + 2:offset + length]
        if marker == 0xE1 and (
            payload.startswith(b"http://ns.adobe.com/xap/1.0/\x00")
            or b"x:xmpmeta" in payload
        ):
            segments.append(payload.decode("utf-8", errors="replace"))
        offset += length
    return segments


def extract_ints(text: str, key: str) -> list[int]:
    patterns = [
        rf"{re.escape(key)}\s*=\s*\"([0-9]+)\"",
        rf"<{re.escape(key)}>\s*([0-9]+)\s*</{re.escape(key)}>",
    ]
    values: list[int] = []
    for pattern in patterns:
        for match in re.finditer(pattern, text):
            values.append(int(match.group(1)))
    return values


def last_mp4_tail(data: bytes) -> dict:
    positions = [match.start() for match in re.finditer(b"ftyp", data)]
    candidates = []
    for pos in positions:
        start = pos - 4
        if start < 0:
            continue
        size = int.from_bytes(data[start:pos], "big")
        if size >= 8 and start + size <= len(data):
            major_brand = data[pos + 4:pos + 8].decode("latin1", errors="replace")
            candidates.append(
                {
                    "start": start,
                    "tail_bytes": len(data) - start,
                    "ftyp_box_size": size,
                    "major_brand": major_brand,
                }
            )
    return candidates[-1] if candidates else {}


def analyze(path: Path) -> dict:
    data = path.read_bytes()
    text = data.decode("utf-8", errors="replace")
    xmp_segments = jpeg_app1_xmp_segments(data)
    xmp_text = "\n".join(xmp_segments) if xmp_segments else text
    micro_offsets = extract_ints(xmp_text, "Camera:MicroVideoOffset")
    micro_offsets += extract_ints(xmp_text, "GCamera:MicroVideoOffset")
    item_lengths = extract_ints(xmp_text, "Item:Length")
    item_lengths += extract_ints(xmp_text, "GContainerItem:Length")
    nonzero_item_lengths = [value for value in item_lengths if value > 0]
    mp4_tail = last_mp4_tail(data)
    tail_bytes = mp4_tail.get("tail_bytes")
    first_jpeg_eoi = data.find(b"\xff\xd9")
    last_jpeg_eoi = data.rfind(b"\xff\xd9")

    return {
        "path": str(path),
        "bytes": len(data),
        "file_type": file_type(data),
        "jpeg_has_eoi": first_jpeg_eoi >= 0,
        "bytes_after_first_jpeg_eoi": len(data) - first_jpeg_eoi - 2 if first_jpeg_eoi >= 0 else None,
        "bytes_after_last_jpeg_eoi": len(data) - last_jpeg_eoi - 2 if last_jpeg_eoi >= 0 else None,
        "xmp_app1_segments": len(xmp_segments),
        "has_xmpmeta": "x:xmpmeta" in xmp_text,
        "has_motion_photo_flag": any(
            token in xmp_text
            for token in (
                'Camera:MotionPhoto="1"',
                'GCamera:MotionPhoto="1"',
                'Camera:MicroVideo="1"',
                'GCamera:MicroVideo="1"',
            )
        ),
        "micro_video_offsets": micro_offsets,
        "container_item_lengths": item_lengths,
        "mp4_tail": mp4_tail or None,
        "micro_offset_matches_mp4_tail": tail_bytes in micro_offsets if tail_bytes else False,
        "container_length_matches_mp4_tail": tail_bytes in nonzero_item_lengths if tail_bytes else False,
        "xmp_namespaces_seen": {
            "Camera": "xmlns:Camera=" in xmp_text or "Camera:MotionPhoto" in xmp_text,
            "GCamera": "xmlns:GCamera=" in xmp_text or "GCamera:MotionPhoto" in xmp_text,
            "Container": "xmlns:Container=" in xmp_text or "Container:Directory" in xmp_text,
            "GContainer": "xmlns:GContainer=" in xmp_text or "GContainer:Directory" in xmp_text,
        },
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: src/analyze_dynamic_photo.py <image-or-motion-photo> [...]", file=sys.stderr)
        return 2
    reports = [analyze(Path(arg).expanduser()) for arg in sys.argv[1:]]
    print(json.dumps(reports if len(reports) > 1 else reports[0], indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
