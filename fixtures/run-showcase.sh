#!/bin/bash
# Replays Haden Rd, Benton County (unpaved), along its real Arkansas GIS centerline.
# 2.15 km through all four curves on the road, about 2.5 minutes at the default speed.
# Usage: bash fixtures/run-showcase.sh [speed m/s, default 15] [simulator UUID or "booted"]
# Park the simulator at the start first: xcrun simctl location booted set 36.22993,-94.28554
# Synthetic simulator input only. The simulator build never uploads.
set -euo pipefail
fixture_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
speed="${1:-15}"
python3 - "$fixture_dir/haden-rd.gpx" <<'PY' | xcrun simctl location "${2:-booted}" start --speed="$speed" --interval=1 -
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for point in root.findall('{http://www.topografix.com/GPX/1/1}wpt'):
    print(point.attrib['lat'] + ',' + point.attrib['lon'])
PY
