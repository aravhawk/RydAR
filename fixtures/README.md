# Simulator route

`old-wire-approach.gpx` approaches the bundled curve `007-2-3`, N Old Wire Rd, Benton County. The curve's own coordinates are copied from `ios/RydAR/curves.sqlite`. The 350 m approach is a synthetic tangent, and the short exit is extrapolated. These are simulator inputs. They are separate from a surveyed centerline and from a recommended driving route. The curve id matches `trace.expect.json` and `old-wire-approach.expect.json`.

Build and install the app in an iPhone simulator. Open it, finish onboarding, then choose **Start trip**, **Driver**, and **Start this trip**. With that simulator booted, run:

```sh
bash fixtures/run-gpx.sh
```

The script plays the GPX with `simctl location start`, at 10 m/s and one fix per second, about 50 seconds. Pass a simulator UUID as the first argument when more than one simulator is booted. Stop with `xcrun simctl location booted clear`. In Xcode, the same file is under Debug → Simulate Location. The script is what sets the speed and the fix interval.

`old-wire-approach.expect.json` records the target, the mode, and the sentence. On a pass, expect one prompt for this curve, exactly "Slow to 11 mph for the curve ahead." End the trip once. The pass shows on Review. Run it again as a Teen driver and expect the same spoken line, with no camera. Sharing follows the same switch as any other trip. A replay of a finished trip stays on the phone.

## Showcase route: Hayden Rd

`hayden-rd-part1.gpx` and `hayden-rd-part2.gpx` follow the Arkansas GIS Office centerline of Hayden Rd, Benton County, south to north. The eight bundled curves on this road lie within 1 m of that line. The route is the real road, with no invented segments. It is meant for screenshots and screen recordings, and the replay never uploads.

| Part | Length | What it shows | Expected warnings at 20 m/s (45 mph) |
|---|---|---|---|
| `part1` | 1.3 km | Two tight bends, about 90 degrees each | "Slow to 17 mph for the curve ahead." then "Slow to 16 mph for the curve ahead." |
| `part2` | 1.9 km | Three bends in 350 m, then two more | "Slow to 24 mph…", "Slow to 16 mph…", "Curves ahead for the next 950 feet, keep it under 24 mph.", then "Curves ahead for the next 850 feet, keep it under 25 mph." |

Park the simulator at the start, then replay:

```sh
xcrun simctl location booted set 36.45810,-94.12321   # part1 start
bash fixtures/run-showcase.sh part1
xcrun simctl location booted set 36.47973,-94.11445   # part2 start
bash fixtures/run-showcase.sh part2
```

Those lines come from running the app's own `TripMatcher` over the route, one fix per second, as Driver, tire answer "Not sure", camera check off. They are the contract for the replay. Speech is audible from the Mac but is not part of a `simctl recordVideo` capture; the advisory also shows on the drive screen. Live Activities only appear once the app leaves the foreground (Home, or lock the simulator with ⌘L).
