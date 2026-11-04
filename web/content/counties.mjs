// Builds the per-county pages from the shipped curve files, so every number on them is the map's own data.
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const dataDir = fileURLToPath(new URL('../public/data/', import.meta.url));
const CURVE_FILES = [1, 2, 3, 4].map((n) => `curves-arkansas-${n}.geojson`);

// Same formula and rounding as the map popup (index.html) and ios/RydAR/Screening.swift.
export const FRICTION = { paved: 0.15, unpaved: 0.1 };
const mph = (radius, e, f) => Math.sqrt(Math.max(0, 15 * radius * (e + f)));
export const speedRange = (radiusFeet, surface) => {
  const f = FRICTION[surface];
  return [Math.floor(mph(radiusFeet, -0.02, f)), Math.floor(mph(radiusFeet, 0.02, f))];
};
export const speedText = (radiusFeet, surface) => speedRange(radiusFeet, surface).join('–') + ' mph';

export const slug = (county) => `${county.toLowerCase().replaceAll('.', '').replaceAll(' ', '-')}-county`;
export const countyPath = (county) => `/arkansas-curve-map/${slug(county)}`;
export const mapLink = (county) => `/?county=${encodeURIComponent(county)}`;
const fmt = (n) => n.toLocaleString('en-US');

// Driveways and placeholder names say nothing useful about a public road.
const unnamed = /^(unnamed|private|pvt|access|drive|driveway)\b|\b(private|pvt|unnamed)\b/i;
// Cul-de-sacs and loops are tight by design; the sharpest-bend list is about roads people drive through.
const deadEnd = /\s(ct|cir|circle|court|pl|place|cv|cove|loop|ter|terrace)\b\.?$/i;

async function readJSON(name) {
  return JSON.parse(await readFile(`${dataDir}${name}`, 'utf8'));
}

function rings(feature) {
  const { type, coordinates } = feature.geometry;
  return type === 'Polygon' ? coordinates : coordinates.flat();
}

function segmentGap([px, py], [ax, ay], [bx, by]) {
  const dx = bx - ax;
  const dy = by - ay;
  const t = dx || dy ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))) : 0;
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

// Counties are "nearby" when their simplified outlines come within about a kilometer of each other.
function neighbors(countyGeo) {
  const gap = 0.01;
  const shapes = countyGeo.features.map((feature) => {
    const outline = rings(feature);
    const points = outline.flat();
    const segments = outline.flatMap((ring) => ring.slice(1).map((point, i) => [ring[i], point]));
    const xs = points.map((p) => p[0]);
    const ys = points.map((p) => p[1]);
    return { name: feature.properties.county, points, segments, box: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)] };
  });
  // A shared border, not a corner: at least ~3 km of one outline runs along the other.
  const step = 0.004;
  const samples = (shape) => shape.segments.flatMap(([[ax, ay], [bx, by]]) => {
    const n = Math.max(1, Math.ceil(Math.hypot(bx - ax, by - ay) / step));
    return Array.from({ length: n }, (_, i) => [ax + ((bx - ax) * i) / n, ay + ((by - ay) * i) / n]);
  });
  for (const shape of shapes) shape.samples = samples(shape);
  const shared = (a, b) => a.samples.filter((point) => b.segments.some(([s, e]) => segmentGap(point, s, e) < gap)).length * step >= 0.03;
  const near = new Map(shapes.map((shape) => [shape.name, []]));
  for (let i = 0; i < shapes.length; i += 1) {
    for (let j = i + 1; j < shapes.length; j += 1) {
      const a = shapes[i];
      const b = shapes[j];
      if (a.box[0] > b.box[2] + gap || b.box[0] > a.box[2] + gap || a.box[1] > b.box[3] + gap || b.box[1] > a.box[3] + gap) continue;
      if (shared(a, b) || shared(b, a)) {
        near.get(a.name).push(b.name);
        near.get(b.name).push(a.name);
      }
    }
  }
  for (const list of near.values()) list.sort();
  return near;
}

async function load() {
  const countyGeo = await readJSON('arkansas-counties.geojson');
  const names = countyGeo.features.map((feature) => feature.properties.county).sort();
  const byCounty = new Map(names.map((name) => [name, { name, total: 0, paved: 0, unpaved: 0, roads: new Map(), sharpest: new Map() }]));
  for (const file of CURVE_FILES) {
    for (const { properties: p } of (await readJSON(file)).features) {
      const county = byCounty.get(p.county);
      if (!county) throw new Error(`Curve ${p.id} names unknown county ${p.county}`);
      county.total += 1;
      county[p.surface] += 1;
      const road = p.road?.trim();
      if (!road || unnamed.test(road)) continue;
      const entry = county.roads.get(road) || { road, curves: 0, paved: 0, unpaved: 0, tightest: Infinity };
      entry.curves += 1;
      entry[p.surface] += 1;
      entry.tightest = Math.min(entry.tightest, p.radius_ft);
      county.roads.set(road, entry);
      if (deadEnd.test(road)) continue;
      const best = county.sharpest.get(road);
      if (!best || p.radius_ft < best.radius_ft || (p.radius_ft === best.radius_ft && p.deflection_deg > best.deflection_deg)) {
        county.sharpest.set(road, p);
      }
    }
  }
  const counties = [...byCounty.values()];
  const ranked = [...counties].sort((a, b) => b.total - a.total);
  ranked.forEach((county, index) => { county.rank = index + 1; });
  const near = neighbors(countyGeo);
  const statewide = {
    total: counties.reduce((sum, c) => sum + c.total, 0),
    paved: counties.reduce((sum, c) => sum + c.paved, 0),
    unpaved: counties.reduce((sum, c) => sum + c.unpaved, 0),
    counties: counties.length,
  };
  return { counties, near, statewide, byCounty };
}

const data = await load();
export const statewide = data.statewide;
export const counties = data.counties.map(({ name, total }) => ({ name, total, path: countyPath(name) }));

const surfaceLabel = (entry) => (entry.paved && entry.unpaved ? 'Paved and unpaved' : entry.paved ? 'Paved' : 'Unpaved');

export function countyPages() {
  return data.counties.map((county) => {
    const { name } = county;
    const full = `${name} County`;
    const share = Math.round((county.unpaved / county.total) * 100);
    // The builder files a road with no recorded surface as unpaved. Where that is nearly every road, say so.
    const surfaceKnown = county.paved / county.total >= 0.03;
    const roads = [...county.roads.values()]
      .sort((a, b) => b.curves - a.curves || a.tightest - b.tightest || a.road.localeCompare(b.road))
      .slice(0, 10);
    const sharpest = [...county.sharpest.values()]
      .sort((a, b) => a.radius_ft - b.radius_ft || b.deflection_deg - a.deflection_deg || a.road.localeCompare(b.road))
      .slice(0, 10);
    const nearby = data.near.get(name).map((other) => data.byCounty.get(other));
    const busiest = roads[0];
    const tightest = Math.min(...[...county.roads.values()].map((road) => road.tightest));
    const blocks = [
      { type: 'stats', items: surfaceKnown ? [
        [fmt(county.total), 'mapped curves'],
        [fmt(county.paved), 'on paved roads'],
        [fmt(county.unpaved), 'on unpaved roads'],
        [`#${county.rank}`, `of ${statewide.counties} counties`],
      ] : [
        [fmt(county.total), 'mapped curves'],
        [fmt(county.roads.size), 'named roads with curves'],
        [`${tightest} ft`, 'tightest named bend'],
        [`#${county.rank}`, `of ${statewide.counties} counties`],
      ] },
    ];
    if (roads.length) {
      blocks.push({
        type: 'table', title: `Curviest roads in ${full}`,
        text: `Named roads with the most mapped bends.${busiest ? ` ${busiest.road} leads with ${fmt(busiest.curves)}.` : ''}`,
        head: ['Road', 'Curves', 'Tightest'],
        numeric: [1, 2],
        rows: roads.map((road) => [
          surfaceKnown ? `${road.road}<span class="sub">${surfaceLabel(road)}</span>` : road.road,
          fmt(road.curves), `${road.tightest} ft`,
        ]),
      });
    }
    if (sharpest.length) {
      blocks.push({
        type: 'table', title: `Sharpest bends in ${full}`,
        text: `The tightest bend on each named road, leaving out courts, circles, and loops.${surfaceKnown ? '' : ' Surface isn’t recorded for most roads here, so speeds use the more cautious unpaved figure.'}`,
        head: ['Road', 'Radius', 'Suggested speed'],
        numeric: [1, 2],
        rows: sharpest.map((curve) => [
          `${curve.road}<span class="sub">${surfaceKnown ? `${curve.surface === 'paved' ? 'Paved' : 'Unpaved'} · ` : ''}${curve.deflection_deg}° turn</span>`,
          `${curve.radius_ft} ft`, speedText(curve.radius_ft, curve.surface),
        ]),
      });
    }
    if (nearby.length) {
      blocks.push({
        type: 'links', title: 'Nearby counties',
        items: nearby.map((other) => [countyPath(other.name), `${other.name} County`, `${fmt(other.total)} curves`]),
      });
    }
    blocks.push({ type: 'note', text: 'Suggested speeds come from each bend’s radius. They are not posted limits; gravel, weather, and worn tires call for slower. <a href="/how-it-works">How it works</a> · Road data: Arkansas GIS Office.' });
    return {
      kind: 'county', county: name,
      path: countyPath(name),
      title: `Curvy Roads in ${full}, AR: Curve Map | RydAR`,
      description: surfaceKnown
        ? `${fmt(county.total)} mapped curves on ${full}, Arkansas roads, ${fmt(county.paved)} paved and ${fmt(county.unpaved)} unpaved. See the curviest roads, the sharpest bends, and suggested speeds.`
        : `${fmt(county.total)} mapped curves on ${fmt(county.roads.size)} named roads in ${full}, Arkansas. See the curviest roads, the sharpest bends, and a suggested speed for each.`,
      heading: `Curvy roads in ${full}`,
      label: full,
      parents: [['/arkansas-curve-map', 'Arkansas curve map']],
      intro: `${fmt(county.total)} mapped bends on ${full}, Arkansas roads, each with a suggested speed.${surfaceKnown ? ` ${share}% are on unpaved roads.` : ''}`,
      action: [`Open ${full} on the map`, mapLink(name)],
      blocks,
    };
  });
}
