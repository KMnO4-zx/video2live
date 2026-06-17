#!/usr/bin/env bash
set -euo pipefail

record_path="${1:-src/latest_xiaomi_xhs_validation_record.md}"

if [[ ! -f "$record_path" ]]; then
  echo "Xiaomi/Xiaohongshu validation record not found: $record_path" >&2
  exit 2
fi

section_between() {
  local start="$1"
  local end="$2"
  awk -v start="$start" -v end="$end" '
    index($0, start) == 1 { inside = 1; next }
    inside && index($0, end) == 1 { exit }
    inside { print }
  ' "$record_path"
}

missing=0

require_pass_row() {
  local start="$1"
  local end="$2"
  local check="$3"
  if ! section_between "$start" "$end" | grep -F "$check" | grep -Fq "| pass | pass |"; then
    echo "Missing pass/pass Xiaomi/Xiaohongshu row in ${start#'## '}: $check" >&2
    missing=1
  fi
}

require_pass_row "## Xiaomi Gallery Checks" "## Xiaohongshu Android Checks" "Motion Photo candidate appears in Xiaomi Gallery"
require_pass_row "## Xiaomi Gallery Checks" "## Xiaohongshu Android Checks" "Xiaomi Gallery recognizes it as dynamic/live photo"
require_pass_row "## Xiaomi Gallery Checks" "## Xiaohongshu Android Checks" "Long-press or motion playback animates"
require_pass_row "## Xiaomi Gallery Checks" "## Xiaohongshu Android Checks" "Cover/key photo matches intended frame/image"

require_pass_row "## Xiaohongshu Android Checks" "## Fallback MP4 Diagnostic" "Motion Photo candidate selectable from Xiaomi Gallery"
require_pass_row "## Xiaohongshu Android Checks" "## Fallback MP4 Diagnostic" "Xiaohongshu import shows live/dynamic-photo behavior before publish"
require_pass_row "## Xiaohongshu Android Checks" "## Fallback MP4 Diagnostic" "Published/draft item preserves live/dynamic-photo behavior"

if grep -Fq "pass/fail" "$record_path"; then
  echo "Xiaomi/Xiaohongshu validation record still contains pass/fail placeholders." >&2
  missing=1
fi

if grep -Eq '\|[[:space:]]*fail[[:space:]]*\|' "$record_path"; then
  echo "Xiaomi/Xiaohongshu validation record contains explicit fail entries." >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  echo "XIAOMI_XHS_VALIDATION_INCOMPLETE"
  exit 1
fi

echo "XIAOMI_XHS_VALIDATION_COMPLETE"
