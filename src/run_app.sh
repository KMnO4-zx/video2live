#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
./build_app.sh
open ".build/release/Video2Live.app"
