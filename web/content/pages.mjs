export const site = {
  origin: 'https://rydar.org',
  name: 'RydAR',
  beta: 'https://testflight.apple.com/join/WRKVeXwc',
  source: 'https://github.com/aravhawk/RydAR',
};

export const home = {
  path: '/',
  title: 'RydAR | Arkansas Curve Map & iPhone Curve Warnings',
  description: 'Explore tight bends on Arkansas county roads with RydAR’s free curve map. Get suggested curve speeds and try the iPhone curve warning app on TestFlight.',
  heading: 'RydAR',
};

export const pages = [
  {
    path: '/arkansas-curve-map',
    title: 'Arkansas Curve Map: County Roads & Suggested Speeds | RydAR',
    description: 'Learn how to use RydAR’s free Arkansas curve map: choose a county, search a road, and inspect paved and unpaved bends with suggested speed ranges.',
    heading: 'Find the bends before you go.',
    label: 'Arkansas curve map',
    intro: 'Explore tight curves on county roads across Arkansas’s 75 counties. RydAR’s free public map shows where bends are, the road surface, and a computed suggested speed range.',
    action: ['Open the curve map', '/'],
    sections: [
      ['How to find curves on an Arkansas road', `<ol><li><strong>Choose a county.</strong> Click a county on the map or use the County menu. You can also leave it set to All of Arkansas.</li><li><strong>Choose a surface.</strong> Keep both Paved and Unpaved selected, or narrow the map to one.</li><li><strong>Find a road.</strong> Type a road name in Find a road, then choose a result.</li><li><strong>Inspect a bend.</strong> Click a curve to see its county, surface, radius, turn angle, and suggested speed range.</li></ol><p>You can browse the map without an account or the iPhone app. The interactive map requires JavaScript; these instructions do not.</p>`],
      ['What the map covers', `<p>The public map contains curves on county-class roads from the Arkansas GIS Office road inventory. It covers all 75 Arkansas counties, including Benton, Washington, Carroll, Newton, Pulaski, and Garland. It is a county-road curve explorer, not an inventory of every bend on every highway.</p><p>Paved and unpaved classifications come from the road data. The map leaves out flagged loops, ramps, connectors, and corners with a radius under 50 feet. A missing curve does not mean a road is straight or safe at a particular speed.</p>`],
      ['What a suggested curve speed means', `<p>RydAR estimates a range from the curve radius and assumptions about road banking and friction. The range is separate from a posted speed limit or an official advisory sign. Weather, visibility, road condition, tires, and the vehicle can require a lower speed.</p><p>Read <a href="/how-it-works">how RydAR calculates curve speeds</a> for the formula, data source, and limitations. Plan your route while parked.</p>`],
      ['Want warnings on your iPhone?', `<p>The web map is for exploring roads. The <a href="/iphone-app">RydAR iPhone app</a> uses a bundled curve database to give spoken warnings before confidently matched bends ahead. The app is available as a free TestFlight beta.</p>`],
    ],
  },
  {
    path: '/iphone-app',
    title: 'RydAR for iPhone | Arkansas Curve Warning App',
    description: 'Try RydAR’s free iPhone beta for spoken curve warnings on Arkansas roads. Learn about suggested speeds, offline curve data, and Teen driver mode.',
    heading: 'A heads-up for the next bend.',
    label: 'RydAR for iPhone',
    intro: 'RydAR is an iPhone co-pilot for tight bends in Arkansas. It uses the road ahead and a curve database bundled in the app to speak a suggested speed before a curve.',
    action: ['Join the free TestFlight beta', site.beta],
    sections: [
      ['Spoken curve warnings', `<p>A warning can say, “Slow to 25 mph for the curve ahead.” The spoken number uses the low end of the calculated range, rounded down. Confidently matched bends on the same named road can share a “Curves ahead” warning, with a separate warning for a notably sharper bend.</p><p>The app normally looks about 12 seconds ahead, with a warning distance between 100 and 450 meters. It skips a warning when there is too little road left to act on it, or when the car is already moving away from the bend. See <a href="/how-it-works">how curve matching and suggested speeds work</a>.</p>`],
      ['Curve data available without loading the website', `<p>The curve database ships inside the iPhone app. A drive does not wait for the website to load or fetch its curve map. GPS reception and a confident road match still matter; if location fixes stop for more than four seconds, the drive screen reports the gap.</p><p>RydAR covers Arkansas. Its bundled inventory does not add a belt of roads in neighboring states. The <a href="/arkansas-curve-map">public Arkansas curve map</a> lets you explore county-road bends before setting out.</p>`],
      ['Driver and Teen driver modes', `<p>Driver mode shows the curve information and supports an optional camera road-surface check. Teen driver mode speaks the same numeric curve advisories, vibrates twice before each one, and lets the screen sleep. Teen driver mode has no camera, curve display, or Live Activity.</p><p>Set up the trip while parked. Suggested speeds do not replace posted signs, attention to the road, or your judgment about conditions.</p>`],
      ['Try the beta', `<p>RydAR is currently distributed through Apple TestFlight. Open the <a href="${site.beta}">RydAR beta invitation</a> on your iPhone and follow Apple’s installation steps. A beta can change and availability depends on TestFlight.</p><p>Read about <a href="/data-and-privacy">camera frames and optional anonymous sharing</a>. The <a href="${site.source}">RydAR source code</a> is public, and you can <a href="${site.source}/issues">report an issue on GitHub</a>.</p>`],
    ],
  },
  {
    path: '/how-it-works',
    title: 'How RydAR Calculates Suggested Curve Speeds | RydAR',
    description: 'Understand RydAR’s Arkansas road data, curve speed formula, warning timing, and limitations. Suggested speeds are separate from posted speed limits.',
    heading: 'What goes into a curve warning.',
    label: 'How RydAR works',
    intro: 'A bend’s shape is a starting point, not a complete picture of driving conditions. RydAR combines mapped road geometry with your position to identify curves ahead and calculate a suggested speed.',
    action: ['Explore the Arkansas map', '/'],
    sections: [
      ['Arkansas road geometry', `<p>The statewide curve database is built from the Arkansas GIS Office’s <a href="https://gis.arkansas.gov/arcgis/rest/services/FEATURESERVICES/Transportation/MapServer/18">ROADS_ACF road layer</a>. RydAR identifies bends in the road centerlines and records measurements such as radius and deflection angle. The public web map shows the county-class road portion of that inventory.</p><p>This is a computed dataset, not a field survey of every curve. Road geometry, surface labels, and road names can be incomplete or out of date. Loops, ramps, and very tight corners are filtered from the public map.</p>`],
      ['The suggested speed calculation', `<p>The base formula is <code>V = √(15 × R × (e + f))</code>, where V is miles per hour, R is radius in feet, e is assumed road banking, and f is an assumed friction value. The public map calculates a range using banking from −0.02 to +0.02 and friction of 0.15 for paved roads or 0.10 for unpaved roads.</p><p>For example, a mapped 300-foot paved curve gives a base range of about 24–27 mph, rounded down. The phone’s tire-tread setting can lower the assumed friction further. These assumptions are not a measurement of the grip available to your tires on that road.</p><p>The iPhone’s spoken advisory uses the low end of its calculated range. Neither the map range nor the app advisory is a posted speed limit or an official traffic-engineering recommendation. Follow signs and choose a speed appropriate to current conditions.</p>`],
      ['Matching the road ahead', `<p>The iPhone app checks your position and direction against nearby curves. A bend far to the side of the line of travel is treated as another road. A warning only plays when there is enough road left before the curve; it stays silent once the car is moving away or the bend is too close.</p><p>The base lead is 12 seconds of travel, clamped to 100–450 meters. The optional camera check can identify a change in road surface and move a warning earlier. It does not turn a camera frame into a new advisory speed.</p>`],
      ['Limits to keep in mind', `<p>GPS errors can affect road matching. Missing data can leave a bend unmarked. Ice, water, gravel, poor sight distance, tire condition, and vehicle differences can make a computed speed unsuitable. RydAR does not guarantee a warning for every curve or that any particular speed is safe.</p><p>Use the <a href="/arkansas-curve-map">map guide</a> to plan while parked, or read about the <a href="/iphone-app">iPhone beta</a>. Implementation details are available in the <a href="${site.source}/blob/main/ios/RydAR/Screening.swift">speed calculation source</a> and <a href="${site.source}/blob/main/tools/build_arkansas.py">Arkansas database builder</a>.</p>`],
    ],
  },
  {
    path: '/data-and-privacy',
    title: 'RydAR Data & Privacy | Camera and Anonymous Sharing',
    description: 'Learn what RydAR does with camera frames, optional anonymous curve passes, and browser location when using the Arkansas map and iPhone app.',
    heading: 'Know what your drive shares.',
    label: 'Data and privacy',
    intro: 'The iPhone app can check the road surface and optionally share anonymous curve passes. Here is how those features work in the current implementation.',
    sections: [
      ['Camera frames stay on the phone', `<p>When the road-surface check runs in Driver mode, the drive screen shows a small live preview and a Paved or Unpaved label. Frames are displayed and processed on the phone; they are not saved or uploaded. Teen driver mode does not use the camera.</p>`],
      ['Anonymous curve sharing is optional', `<p>When uploads are enabled, anonymous curve passes are held until the trip ends, then sent together in random order. They are sent only if uploads are still enabled when the trip ends. Simulator builds do not upload passes.</p><p>A pass includes a curve identifier, travel direction, speed value, hour bucket, and app version. The server stores the day of arrival rather than its exact time. Curve and time information can still be sensitive; turn off sharing if you do not want to contribute passes.</p><p>The public county CSV exports contain aggregated counts per curve and the number of distinct hour buckets, not individual trip records. Read the <a href="${site.source}/blob/main/web/server.ts">API implementation</a> for the fields stored and exported.</p>`],
      ['Location and the web map', `<p>Your browser may ask for location access to position the <a href="/">Arkansas curve map</a> near you. You can decline and choose a county manually. RydAR’s map code uses that location locally to position the view; it does not post it to the anonymous-pass API.</p><p>The map loads basemap styles and tiles from <a href="https://openfreemap.org/">OpenFreeMap</a>. Those requests, as well as requests to the RydAR hosting provider, expose ordinary connection information such as an IP address. Apple’s TestFlight and GitHub have their own privacy terms when you follow their links.</p>`],
      ['Questions about the implementation', `<p>RydAR’s <a href="${site.source}">source code is public</a>. You can <a href="${site.source}/issues">open an issue</a> with a question or bug report. Avoid including personal trip details in a public issue.</p><p>Learn more about <a href="/how-it-works">curve warnings and their limitations</a> or <a href="/iphone-app">the iPhone beta</a>.</p>`],
    ],
  },
];
