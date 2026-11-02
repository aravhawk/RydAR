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
    intro: 'A free map of curves on Arkansas county roads, with a suggested speed for each.',
    action: ['Open the map', '/'],
    blocks: [
      { type: 'steps', items: [
        ['Pick a county', 'Or stay on all of Arkansas.'],
        ['Choose paved or unpaved', 'Show one surface or both.'],
        ['Search a road', 'Type a name and pick a result.'],
        ['Tap a curve', 'See its radius, turn angle, and suggested speed.'],
      ] },
      { type: 'tiles', items: [
        ['pin', 'All 75 counties', 'County roads, paved and unpaved.'],
        ['gauge', 'Suggested, not posted', 'A computed range. See <a href="/how-it-works">how it works</a>.'],
      ] },
    ],
  },
  {
    path: '/iphone-app',
    title: 'RydAR for iPhone | Arkansas Curve Warning App',
    description: 'Try RydAR’s free iPhone beta for spoken curve warnings on Arkansas roads. Learn about suggested speeds, offline curve data, and Teen driver mode.',
    heading: 'A heads-up for the next bend.',
    label: 'RydAR for iPhone',
    intro: 'RydAR speaks a suggested speed before tight curves in Arkansas.',
    action: ['Join the free beta', site.beta],
    blocks: [
      { type: 'tiles', items: [
        ['speaker', 'Spoken warnings', '“Slow to 25 mph for the curve ahead.”'],
        ['database', 'Curves built in', 'The Arkansas curve database lives inside the app.'],
        ['wheel', 'Driver mode', 'Curve info on screen, plus an optional camera road check.'],
        ['person', 'Teen driver mode', 'Spoken warnings and two buzzes. No screen, no camera.'],
      ] },
      { type: 'note', text: 'Free on TestFlight. Set up while parked.' },
    ],
  },
  {
    path: '/how-it-works',
    title: 'How RydAR Calculates Suggested Curve Speeds | RydAR',
    description: 'Understand RydAR’s Arkansas road data, curve speed formula, warning timing, and limitations. Suggested speeds are separate from posted speed limits.',
    heading: 'What goes into a curve warning.',
    label: 'How it works',
    intro: 'Road shape, a simple formula, and your position.',
    action: ['Open the map', '/'],
    blocks: [
      { type: 'steps', items: [
        ['Road data', `Bends are measured from the Arkansas GIS Office <a href="https://gis.arkansas.gov/arcgis/rest/services/FEATURESERVICES/Transportation/MapServer/18">road lines</a>.`],
        ['Suggested speed', 'Radius, banking, and friction give a range.'],
        ['Timing', 'The app speaks up about 12 seconds ahead. It stays quiet if the bend is behind you or too close.'],
      ] },
      { type: 'formula', formula: 'V = √(15 · R · (e + f))', terms: ['V speed, mph', 'R radius, ft', 'e banking', 'f friction'], text: 'A 300 ft paved curve gives about 24–27 mph.' },
      { type: 'note', text: `A guide, not a posted limit. Gravel, weather, tires, or GPS error can call for slower. <a href="${site.source}/blob/main/ios/RydAR/Screening.swift">Read the code</a>.` },
    ],
  },
  {
    path: '/data-and-privacy',
    title: 'RydAR Data & Privacy | Camera and Anonymous Sharing',
    description: 'Learn what RydAR does with camera frames, optional anonymous curve passes, and browser location when using the Arkansas map and iPhone app.',
    heading: 'What your drive shares.',
    label: 'Data and privacy',
    intro: 'Very little. Here is exactly what.',
    blocks: [
      { type: 'tiles', items: [
        ['camera', 'Camera stays on the phone', 'Frames are checked on the phone. Never saved or uploaded.'],
        ['share', 'Anonymous curve data', 'After a trip, curve, direction, speed, and hour are sent together. Turn it off in Settings.'],
        ['pin', 'Map location is optional', 'Your browser may offer to center the map on you. It stays in your browser.'],
      ] },
      { type: 'note', text: `Map tiles come from OpenFreeMap. Questions? <a href="${site.source}/issues">Open an issue</a>.` },
    ],
  },
];
