# RydAR

An iPhone co-pilot for tight Arkansas bends, and a public map of those bends. The long product brief is not in this repository. The rules below are the ones the code has to keep.

Repository: [github.com/aravhawk/RydAR](https://github.com/aravhawk/RydAR)

Public map: [rydar.org](https://rydar.org)

## Stack

- iOS 17, SwiftUI, MapKit, one bundled SQLite file for the curves and the trips
- The public site is plain HTML on Vercel. Anonymous passes go to Neon. A drive does not wait on either.
- One bundled vision model, MobileNetV4-Conv-Small with three heads, trained on RSCD and converted to Core ML. Dash loads it. Launch does not. It can only lower a paved label to unpaved, or move a warning earlier. It does not change the advisory speed. Do not quote an accuracy number in the app or in a video.
- A second on-device model, `OnsetNet`, remembers where this phone starts braking and can place the warning sooner. A measured start on that road wins over the network. It does not change the advisory speed.

The spoken line is exactly "Curve ahead. Above advisory speed."

## App

```bash
open ios/RydAR.xcodeproj
```

Builds need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The team is `XLR6H6DKHH`. The phone has to be unlocked to install. The curve database and the model are already in the app. Do not rebuild the SQLite file and do not download curves after install.

## Website

The live site deploys from `main`, with the Vercel project rooted at `web/`. Do not point the phone back at the old Cloudflare worker. That worker is still up and should be left alone.
