# Simulator route

`old-wire-approach.gpx` approaches the bundled curve `007-2-3`, N Old Wire Rd, Benton County. The curve's own coordinates are copied from `ios/RydAR/curves.sqlite`. The 350 m approach is a synthetic tangent, and the short exit is extrapolated. These are simulator inputs. They are separate from a surveyed centerline and from a recommended driving route. The curve id matches `trace.expect.json` and `old-wire-approach.expect.json`.

Build and install the app in an iPhone simulator. Open it, finish onboarding, then choose **Start trip**, **Driver**, and **Start this trip**. With that simulator booted, run:

```sh
bash fixtures/run-gpx.sh
```

The script plays the GPX with `simctl location start`, at 10 m/s and one fix per second, about 50 seconds. Pass a simulator UUID as the first argument when more than one simulator is booted. Stop with `xcrun simctl location booted clear`. In Xcode, the same file is under Debug → Simulate Location. The script is what sets the speed and the fix interval.

`old-wire-approach.expect.json` records the target, the mode, and the sentence. On a pass, expect one prompt for this curve, exactly "Slow to 11 mph for the curve ahead." End the trip once. The pass shows on Review. Run it again as a Teen driver and expect the same spoken line, with no camera. Sharing follows the same switch as any other trip. A replay of a finished trip stays on the phone.

## Showcase route: Haden Rd

`haden-rd.gpx` follows the Arkansas GIS Office centerline of Haden Rd, Benton County (unpaved), south to north, for 2.15 km through all four bundled curves on the road (`007-517-1496`, `1495`, `1492`, `1491`). They lie within 1 m of that line. The route is the real road, with no invented segments. It is meant for screenshots and screen recordings, and the replay never uploads.

Park the simulator at the start, then replay (about 2.5 minutes at 15 m/s, 33 mph):

```sh
xcrun simctl location booted set 36.22993,-94.28554
bash fixtures/run-showcase.sh
```

Expected spoken lines, from running the app's own `TripMatcher` over the route at 15 m/s, one fix per second, as Driver, tire answer "Not sure", camera check off:

1. "Slow to 10 mph for the curve ahead." (R 99 ft gravel bend)
2. "Slow to 17 mph for the curve ahead." (the gentler 248 ft bend right after it)
3. "Slow to 13 mph for the curve ahead." (R 150 ft)
4. "Slow to 12 mph for the curve ahead." (R 136 ft)

Speech is audible from the Mac but is not part of a `simctl recordVideo` capture; the advisory also shows on the drive screen. Live Activities only appear once the app leaves the foreground (Home, or lock the simulator with ⌘L).
