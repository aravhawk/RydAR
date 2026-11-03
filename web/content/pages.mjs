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
    title: 'RydAR Privacy Policy | Camera, Location & Anonymous Sharing',
    description: 'RydAR’s privacy policy: what the iPhone app and Arkansas curve map collect, how anonymous curve passes are signed and kept, and how to turn sharing off.',
    heading: 'What your drive shares.',
    label: 'Data and privacy',
    intro: 'Very little. Here is exactly what, in the app and on this site.',
    blocks: [
      { type: 'tiles', items: [
        ['camera', 'Camera stays on the phone', 'Frames are checked on the phone. Never saved or uploaded.'],
        ['share', 'Anonymous curve data, your choice', 'After a trip: curve, direction, speed, and hour. You choose in setup and can turn it off in Settings.'],
        ['pin', 'Map location is optional', 'Your browser may offer to center the map on you. It stays in your browser.'],
      ] },
      { type: 'policy', updated: 'November 2, 2026', sections: [
        ['What the app sends', [
          'Only if <strong>Share anonymous curve data</strong> is on. You choose during setup, and you can change it anytime in Settings.',
          'After each trip, for each curve you passed, the app sends:',
          { list: [
            'the curve’s ID in the Arkansas road data',
            'your direction of travel (N, NE, E, and so on)',
            'your speed approaching the curve',
            'the hour of day (0 to 23)',
            'the app version',
          ] },
          'They go in one batch, in random order, after the trip ends. Nothing is sent during a drive.',
          'Never sent: your name, contact details, route, GPS coordinates, trip start or end times, camera frames, motion data, or an advertising identifier. RydAR has no accounts.',
        ]],
        ['How the server knows a batch came from RydAR', [
          'The first time the app shares, it makes a signing key inside your iPhone’s Secure Enclave, and Apple’s App Attest confirms the key belongs to the genuine RydAR app on a real iPhone. Each trip’s batch is then signed with that key, which shows nothing in it was changed and that it isn’t a copy of an earlier batch.',
          'For each key, the server keeps a one-way fingerprint of the key’s ID, its public key, a counter that blocks replays, and the last day it was used. That record is never stored with or linked to your passes, and it is deleted after 180 days without use. The key itself never leaves your iPhone and isn’t backed up.',
          'Turning sharing off or resetting all data deletes the key. If you share again, the app makes a new one, so later trips can’t be connected to earlier ones.',
        ]],
        ['What the server keeps', [
          'The five values above for each pass, plus the day it arrived (the day, not the time). RydAR does not store IP addresses. A stored pass can’t be traced back to you, your phone, or a trip.',
        ]],
        ['How it’s used', [
          'To show how drivers take each curve on the public map at rydar.org and in per-county downloads, which list how many passes each curve has and in how many different hours. It is not sold, not used for advertising, not used to track you, and not combined with other data.',
        ]],
        ['Who else handles data', [
          { list: [
            '<strong>Vercel</strong> hosts this site and the upload service. It handles network connections, including IP addresses, to deliver requests.',
            '<strong>Neon</strong> hosts the database of anonymous passes.',
            '<strong>Apple</strong> provides App Attest and Apple Maps. During a trip, when you’re stopped, the app asks Apple to turn your position into a street and town name for the screen. Apple’s privacy policy covers those requests.',
            '<strong>OpenFreeMap</strong> serves the map tiles on this site.',
          ] },
          'These providers handle data only to provide their service to RydAR, and they are expected to protect it at least as well as this policy does. Nobody else receives it.',
        ]],
        ['What stays on your iPhone', [
          'Your trips, the curves you passed, where you tend to brake (used to time later warnings), your tire answer, and your settings stay on the phone. They are not uploaded.',
          'The camera check reads frames in memory and never saves them. Motion data is used during a trip only to notice braking. Location is used for the trip, for the map, and to check that you’re in Arkansas.',
          'If a trip’s batch can’t be sent right away, it waits on the phone and is tried again later. It is deleted once sent, after five tries, or after 14 days, whichever comes first. It is never included in backups.',
        ]],
        ['How long data is kept', [
          { list: [
            'Anonymous passes on the server: kept indefinitely to build the map.',
            'Signing-key records on the server: deleted after 180 days without use.',
            'Data on your iPhone: until you reset it or delete the app.',
          ] },
        ]],
        ['Your choices', [
          { list: [
            '<strong>Stop sharing:</strong> turn off Share anonymous curve data in Settings. Future trips aren’t shared, and batches still waiting on your phone and the signing key are deleted.',
            '<strong>Delete what’s on your phone:</strong> Settings → Reset all data (this also deletes the signing key), or delete the app.',
            '<strong>Permissions:</strong> change location, camera, and motion access anytime in the iPhone’s Settings → RydAR.',
          ] },
          'Passes that were already sent can’t be linked to you, so they can’t be found or deleted one by one. Turning sharing off stops all further collection.',
        ]],
        ['Children and teens', [
          'Teen driver mode is meant for learners and new drivers. RydAR has no accounts and doesn’t knowingly collect personal information from anyone, including children under 13. Teen trips follow the same sharing switch.',
        ]],
        ['This website', [
          'The site uses no cookies, analytics, or ads. If you allow it, your browser centers the map on you, and that location stays in your browser.',
        ]],
        ['Changes and questions', [
          'If this policy changes, the date below changes too. A change that would share more will ask you in the app first.',
          `Questions or requests: <a href="${site.source}/issues">open an issue on GitHub</a>.`,
        ]],
      ] },
    ],
  },
];
