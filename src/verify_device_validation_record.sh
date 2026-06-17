#!/usr/bin/env bash
set -euo pipefail

record_path="${1:-src/latest_device_validation_record.md}"

if [[ ! -f "$record_path" ]]; then
  echo "Device validation record not found: $record_path" >&2
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

require_pass_row() {
  local start="$1"
  local end="$2"
  local check="$3"
  if ! section_between "$start" "$end" | grep -F "$check" | grep -Fq "| pass | pass |"; then
    echo "Missing pass/pass device validation row in ${start#'## '}: $check" >&2
    missing=1
  fi
}

missing=0

require_pass_row "## iPhone Photos Checks" "## WeChat Moments Checks" "Appears in iPhone Photos > Albums > Video2Live"
require_pass_row "## iPhone Photos Checks" "## WeChat Moments Checks" "Opens with Live badge"
require_pass_row "## iPhone Photos Checks" "## WeChat Moments Checks" "Long-press playback animates"
require_pass_row "## iPhone Photos Checks" "## WeChat Moments Checks" "Cover/key photo matches intended frame/image"

require_pass_row "## WeChat Moments Checks" "## Xiaohongshu Checks" "Selectable from iPhone Photos"
require_pass_row "## WeChat Moments Checks" "## Xiaohongshu Checks" "Preview/publish flow accepts the item"
require_pass_row "## WeChat Moments Checks" "## Xiaohongshu Checks" "Published/test-visible post preserves expected motion behavior"

require_pass_row "## Xiaohongshu Checks" "## Completion Gate" "Selectable from iPhone Photos"
require_pass_row "## Xiaohongshu Checks" "## Completion Gate" "Publish/draft flow accepts the item"
require_pass_row "## Xiaohongshu Checks" "## Completion Gate" "Posted/draft item preserves expected motion behavior"

if grep -Fq "pass/fail" "$record_path"; then
  echo "Device validation record still contains pass/fail placeholders." >&2
  missing=1
fi

if grep -Eq '\|[[:space:]]*fail[[:space:]]*\|' "$record_path"; then
  echo "Device validation record contains explicit fail entries." >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  echo "DEVICE_VALIDATION_INCOMPLETE"
  exit 1
fi

echo "DEVICE_VALIDATION_COMPLETE"
