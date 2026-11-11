#!/bin/bash
# Replays fixtures/scenic-dr-showcase.gpx: 14 real curves on Scenic Dr, Benton County, about 2.5 km.
# Usage: bash fixtures/run-showcase.sh [speed m/s, default 16] [simulator UUID or "booted"]
# Synthetic simulator input only. The simulator build never uploads.
set -euo pipefail
fixture_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
speed="${1:-16}"
python3 - "$fixture_dir/scenic-dr-showcase.gpx" <<'PY' | xcrun simctl location "${2:-booted}" start --speed="$speed" --interval=1 -
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for point in root.findall('{http://www.topografix.com/GPX/1/1}wpt'):
    print(point.attrib['lat'] + ',' + point.attrib['lon'])
PY
