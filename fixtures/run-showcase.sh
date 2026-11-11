#!/bin/bash
# Replays part of Hayden Rd, Benton County, along its real Arkansas GIS centerline.
#   part1  1.3 km, two tight bends of about 90 degrees: two single-curve warnings
#   part2  1.9 km, three bends in 350 m then two more: a grouped "Curves ahead" warning
# Usage: bash fixtures/run-showcase.sh [part1|part2] [speed m/s, default 20] [simulator UUID or "booted"]
# Park the simulator at the part's start first (printed by `bash fixtures/run-showcase.sh where`).
# Synthetic simulator input only. The simulator build never uploads.
set -euo pipefail
fixture_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
part="${1:-part1}"
if [ "$part" = "where" ]; then
  echo "part1 start: xcrun simctl location booted set 36.45810,-94.12321"
  echo "part2 start: xcrun simctl location booted set 36.47973,-94.11445"
  exit 0
fi
case "$part" in part1|part2) ;; *) echo "usage: $0 [part1|part2|where] [speed m/s] [simulator]" >&2; exit 2 ;; esac
speed="${2:-20}"
python3 - "$fixture_dir/hayden-rd-$part.gpx" <<'PY' | xcrun simctl location "${3:-booted}" start --speed="$speed" --interval=1 -
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for point in root.findall('{http://www.topografix.com/GPX/1/1}wpt'):
    print(point.attrib['lat'] + ',' + point.attrib['lon'])
PY
