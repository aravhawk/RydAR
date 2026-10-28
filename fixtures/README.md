# Simulator route

`old-wire-approach.gpx` approaches the bundled curve `007-2-3`, N Old Wire Rd, Benton County. The curve's own coordinates are copied from `ios/RydAR/curves.sqlite`. The 350 m approach is a synthetic tangent, and the short exit is extrapolated. These are simulator inputs. They are separate from a surveyed centerline and from a recommended driving route. The curve id matches `trace.expect.json` and `old-wire-approach.expect.json`.

Build and install the app in an iPhone simulator. Open it, finish onboarding, then choose **Start trip**, **Driver**, and **Start this trip**. With that simulator booted, run:

```sh
bash fixtures/run-gpx.sh
```

The script plays the GPX with `simctl location start`, at 10 m/s and one fix per second, about 50 seconds. Pass a simulator UUID as the first argument when more than one simulator is booted. Stop with `xcrun simctl location booted clear`. In Xcode, the same file is under Debug → Simulate Location. The script is what sets the speed and the fix interval.

`old-wire-approach.expect.json` records the target, the mode, and the sentence. On a pass, expect one prompt for this curve, exactly "Slow to 11 mph for the curve ahead." End the trip once. The pass shows on Review. Run it again as a Teen driver and expect the same spoken line, with no haptic, no camera, and no upload. A replay of a finished trip stays on the phone.
