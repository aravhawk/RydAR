# Mac B simulator route

`old-wire-approach.gpx` approaches the real bundled curve `007-2-3`, N Old Wire Rd, Benton County. The target's 21 coordinates are copied from `ios/RydAR/curves.sqlite`. The 350 m approach is a **synthetic tangent extension**, and the short exit is extrapolated. These are simulator inputs, not surveyed road geometry or a recommended driving route. It matches the curve ID in `trace.expect.json`.

Build and install the app in an iPhone simulator. Open it, finish onboarding, select **Start trip → Passenger operating → Start this trip**. With that simulator booted, run:

```sh
bash fixtures/run-gpx.sh
```

The script plays the GPX waypoints with `simctl location start`, at 10 m/s and one fix per second (about 50 seconds). Supply a simulator UUID as its first argument if multiple devices are booted. Stop with `xcrun simctl location booted clear`. In Xcode you can also select this GPX from Debug → Simulate Location. The command-line runner explicitly controls speed and fix interval.

`old-wire-approach.expect.json` records the target, mode, and expected sentence. Verify one prompt for this curve on a pass, exactly “Curve ahead. Above advisory speed.”, with no numeric speed. End the trip once, without a second confirmation, and the pass is on the review. Re-run with an under-18 driver and verify no sound, camera, or upload. Replay must never upload.
