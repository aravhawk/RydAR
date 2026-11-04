import { counties, statewide, speedText } from './counties.mjs';

const fmt = (n) => n.toLocaleString('en-US');

export const site = {
  origin: 'https://rydar.org',
  name: 'RydAR',
  beta: 'https://testflight.apple.com/join/WRKVeXwc',
  source: 'https://github.com/aravhawk/RydAR',
  // Spellings and descriptions people use when they search for the product itself.
  alternateNames: ['Rydar', 'RydAR: Safe Driving', 'RydAR Arkansas', 'RydAR Curve Map', 'RydAR app'],
  slogan: 'Safe Driving',
};

export const home = {
  path: '/',
  title: 'RydAR: Arkansas Curve Map & Curve Warning App for iPhone',
  description: `RydAR maps ${fmt(statewide.total)} curves on Arkansas roads, with a suggested speed for each. Find curvy roads by county, or get spoken curve warnings on iPhone.`,
  heading: 'RydAR',
};

export const pages = [
  {
    path: '/arkansas-curve-map',
    title: 'Arkansas Curve Map: Curvy Roads in All 75 Counties | RydAR',
    description: `A free map of ${fmt(statewide.total)} curves on Arkansas roads in all 75 counties. Find curvy roads and sharp bends by county, with a suggested speed for each.`,
    heading: 'Find the bends before you go.',
    label: 'Arkansas curve map',
    intro: 'A free map of curves on Arkansas roads, with a suggested speed for each.',
    action: ['Open the map', '/'],
    dataset: true,
    blocks: [
      { type: 'stats', items: [
        [fmt(statewide.total), 'mapped curves'],
        [fmt(statewide.paved), 'on paved roads'],
        [fmt(statewide.unpaved), 'unpaved or unrecorded'],
        [String(statewide.counties), 'counties'],
      ] },
      { type: 'steps', items: [
        ['Pick a county', 'Or stay on all of Arkansas.'],
        ['Choose paved or unpaved', 'Show one surface or both.'],
        ['Search a road', 'Type a name and pick a result.'],
        ['Tap a curve', 'See its radius, turn angle, and suggested speed.'],
      ] },
      { type: 'tiles', items: [
        ['pin', 'All 75 counties', 'Highways, county roads, and gravel roads.'],
        ['gauge', 'Suggested, not posted', 'A computed range. See <a href="/how-it-works">how it works</a>.'],
      ] },
      { type: 'links', id: 'counties', title: 'Curvy roads by county', columns: true,
        items: counties.map((county) => [county.path, `${county.name} County`, `${fmt(county.total)} curves`]) },
      { type: 'faq', items: [
        ['Where are the curviest roads in Arkansas?', `By count of mapped bends, the most are in ${counties.toSorted((a, b) => b.total - a.total).slice(0, 3).map((c) => `<a href="${c.path}">${c.name} County</a>`).join(', ')}. Each county page lists its curviest roads and sharpest bends.`],
        ['What counts as a curve?', 'A bend tighter than 600 ft in radius. Loops, ramps, and corners under 50 ft are left out.'],
        ['Does the map show gravel roads?', 'Yes. Paved and unpaved roads are shown in different colors, and you can turn either off.'],
        ['Is the map free?', 'Yes. It works in any browser, with no account.'],
      ] },
    ],
  },
  {
    path: '/iphone-app',
    title: 'RydAR for iPhone: Curve Warning App for Arkansas Roads',
    description: 'RydAR is a free iPhone app that speaks a suggested speed before tight curves on Arkansas roads. Curve data built in, plus a Teen driver mode. Join the beta.',
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
      { type: 'faq', items: [
        ['Is RydAR free?', 'Yes. The beta is free on TestFlight, with no account and no ads.'],
        ['Does it need a cell signal?', 'No. The Arkansas curve database ships inside the app, so warnings don’t wait on the network.'],
        ['Does it work outside Arkansas?', 'Curve warnings cover Arkansas roads for now. A trip that leaves the state keeps running and says it has no curve data there.'],
        ['Is the suggested speed a speed limit?', 'No. It is a computed range for the bend, separate from any posted sign. <a href="/how-it-works">How it works</a>.'],
        ['Is it good for teen drivers?', 'Teen driver mode speaks the same curve warnings and buzzes twice before each one, with no screen to look at and no camera.'],
        ['Is there an Android app?', 'RydAR is an iPhone app. The <a href="/arkansas-curve-map">curve map</a> works in any browser, including on Android.'],
      ] },
      { type: 'note', text: 'Free on TestFlight. Set up while parked.' },
    ],
  },
  {
    path: '/how-it-works',
    title: 'How RydAR Calculates a Safe Curve Speed | RydAR',
    description: 'How RydAR finds curves in Arkansas road data, calculates a suggested curve speed from radius, banking, and friction, and times each warning.',
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
      { type: 'faq', items: [
        ['Why a range and not one number?', 'Banking is rarely recorded, so the formula runs from −2% to +2%. The app speaks the low end, rounded down.'],
        ['What friction does RydAR use?', '0.15 on paved roads and 0.10 on unpaved roads. Worn tires lower both.'],
        ['How early does the warning come?', 'About 12 seconds of travel ahead, kept between 100 and 450 m. With less than 3 seconds left, it stays quiet.'],
        ['Can I try the formula?', 'Yes. The <a href="/curve-speed-calculator">curve speed calculator</a> uses the same one.'],
      ] },
      { type: 'note', text: `A guide, not a posted limit. Gravel, weather, tires, or GPS error can call for slower. <a href="${site.source}/blob/main/ios/RydAR/Screening.swift">Read the code</a>.` },
    ],
  },
  {
    path: '/curve-speed-calculator',
    title: 'Curve Speed Calculator: Safe Speed from Radius | RydAR',
    description: 'Free curve speed calculator. Enter a curve’s radius to get a suggested safe speed in mph for paved or unpaved roads, from V = √(15R(e + f)).',
    heading: 'How fast for this curve?',
    label: 'Curve speed calculator',
    intro: 'Enter a bend’s radius for a suggested speed, from the same formula RydAR uses.',
    script: true,
    blocks: [
      { type: 'calculator', radius: 300 },
      { type: 'table', title: 'Suggested speed by radius', text: 'Banking from −2% to +2%. Friction 0.15 paved, 0.10 unpaved.',
        head: ['Radius', 'Paved', 'Unpaved'], numeric: [0, 1, 2],
        rows: [50, 75, 100, 150, 200, 250, 300, 400, 500, 600, 800, 1000].map((r) => [`${fmt(r)} ft`, speedText(r, 'paved'), speedText(r, 'unpaved')]) },
      { type: 'faq', items: [
        ['How is a safe curve speed calculated?', 'V = √(15 · R · (e + f)), with V in mph, R the radius in feet, e the banking, and f the side friction. Engineers use the same relation to design curves.'],
        ['How do I find a curve’s radius?', 'Tap any Arkansas curve on the <a href="/">RydAR map</a> to see its radius. In the field, measure a chord C and the middle ordinate M; then R = C² ÷ 8M + M ÷ 2.'],
        ['Why is unpaved slower?', 'Gravel and dirt grip less, so the formula uses 0.10 friction instead of 0.15.'],
        ['Is this the advisory speed on the yellow sign?', 'Not necessarily. Posted advisory speeds are set by the road agency. Use this as a guide, and drive slower in rain, on gravel, or with worn tires.'],
      ] },
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
