#!/bin/bash
set -euo pipefail
fixture_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# simctl interpolates these same GPX waypoints at 10 m/s, one fix per second.
# Synthetic test input only; this script has no upload or speech implementation.
python3 - "$fixture_dir/old-wire-approach.gpx" <<'PY' | xcrun simctl location "${1:-booted}" start --speed=10 --interval=1 -
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for point in root.findall('{http://www.topografix.com/GPX/1/1}wpt'):
    print(point.attrib['lat'] + ',' + point.attrib['lon'])
PY
