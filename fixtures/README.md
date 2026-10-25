# Mac B simulator route

`old-wire-approach.gpx` approaches the real bundled curve `007-2-3`, N Old Wire Rd, Benton County. The target's 21 coordinates are copied from `ios/CurveAudit/curves.sqlite`. The 350 m approach is a **synthetic tangent extension**, and the short exit is extrapolated. These are simulator inputs, not surveyed road geometry or a recommended driving route. It matches the curve ID in `trace.expect.json`.

Build and install the app in an iPhone simulator. Open it, finish onboarding, select **Start trip → Passenger operating → Start this trip**. With that simulator booted, run:

```sh
bash fixtures/run-gpx.sh
```

The script plays the GPX waypoints with `simctl location start`, at 10 m/s and one fix per second (about 50 seconds). Supply a simulator UUID as its first argument if multiple devices are booted. Stop with `xcrun simctl location booted clear`. In Xcode you can also select this GPX from Debug → Simulate Location. The command-line runner explicitly controls speed and fix interval.

`old-wire-approach.expect.json` records the target, mode, and expected sentence. When Mac A's drive engine is connected, verify one prompt for this curve/pass, exactly **“Curve ahead. Above screening range.”**, with no numeric speed; pause, confirm parked, and verify the saved pass in debrief. Re-run with Under-18 driver and verify no sound, camera, or moving upload. Replay must never upload.

The default app is a screen preview with `PreviewCurves`. It does not synthesize location matching, speech, or saved trip passes. Location playback can run before the engine is connected, but a silent preview is not evidence that engine gates pass.
