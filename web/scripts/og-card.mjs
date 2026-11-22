// Draws the 1200x630 social cards (Open Graph and Twitter) and renders them to PNG.
//
// The look is public/og-image.png, measured rather than eyeballed: flat teal ground, the app tile and
// wordmark top left, a bold white headline, and a road bending in from the right with a dashed centerline.
// Calling renderCard({ title: ['Safe', 'Driving.'] }) reproduces that image. Every other page changes
// only its headline and one cyan line beneath it.
//
// Text is Liberation Sans Bold (SIL Open Font License, see fonts/), the Arial-metric face that image uses.
// Fonts are loaded from the repo and never from the system, so a card renders the same on any machine.
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

export const WIDTH = 1200;
export const HEIGHT = 630;

const FONT_FILE = fileURLToPath(new URL('./fonts/LiberationSans-Bold.ttf', import.meta.url));
const FAMILY = 'Liberation Sans';
const resvgOptions = { font: { fontFiles: [FONT_FILE], loadSystemFonts: false, defaultFontFamily: FAMILY } };

// Same values as the site (--accent, theme-color) and the existing og-image.png.
const COLOR = { ground: '#062e38', road: '#0e4452', line: '#30b0c7', wordmark: '#b9dfe8', ink: '#ffffff', sub: '#30b0c7' };

const CAP_HEIGHT = 0.688; // Liberation Sans Bold, in em
const MARGIN = 90; // left edge of everything
const TEXT_WIDTH = 600; // keeps text 35px or more clear of the road, which starts at x=725
const MARK = 72; // app tile size
const MARK_GAP = 56; // tile bottom to headline cap line
const SUB_GAP = 44; // last headline baseline to the line beneath it
const MAX_BLOCK = HEIGHT - 140; // 70px of air above and below the whole block

// Each pass is tried in order, biggest size first. Fewer lines win while the type stays large, so a
// headline takes two big lines before it takes three smaller ones, and a short line stays on one line.
const TITLE = { passes: [{ sizes: range(104, 80, 2), maxLines: 2 }, { sizes: range(104, 72, 2), maxLines: 3 }], tracking: -0.04, lineHeight: 1 };
const SUB = { passes: [{ sizes: [44, 40, 36], maxLines: 1 }, { sizes: [40, 36], maxLines: 2 }], tracking: -0.02, lineHeight: 1.2 };

function range(from, to, step) {
  const out = [];
  for (let value = from; value >= to; value -= step) out.push(value);
  return out;
}

const escapeXml = (value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

const text = (value, { x, y, size, tracking, fill }) =>
  `<text x="${x}" y="${y}" font-family="${FAMILY}" font-weight="700" font-size="${size}" letter-spacing="${(tracking * size).toFixed(2)}" fill="${fill}">${escapeXml(value)}</text>`;

// Ink width of a string, from the renderer itself so kerning and tracking are counted.
const widths = new Map();
function width(value, size, tracking) {
  const key = `${size}|${tracking}|${value}`;
  if (!widths.has(key)) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${HEIGHT}">${text(value, { x: 0, y: 300, size, tracking, fill: '#000' })}</svg>`;
    const box = new Resvg(svg, resvgOptions).getBBox();
    widths.set(key, box ? box.width + box.x : 0);
  }
  return widths.get(key);
}

function greedy(words, size, tracking, limit) {
  const lines = [];
  for (const word of words) {
    const last = lines.length - 1;
    if (last >= 0 && width(`${lines[last]} ${word}`, size, tracking) <= limit) lines[last] += ` ${word}`;
    else lines.push(word);
  }
  return lines;
}

// Fewest lines that fit, then the narrowest width that keeps that line count, so lines come out
// even and a lone word never sits on the last line.
function balance(value, size, tracking, limit) {
  const words = value.split(/\s+/).filter(Boolean);
  const count = greedy(words, size, tracking, limit).length;
  let low = Math.max(...words.map((word) => width(word, size, tracking)));
  let high = limit;
  while (high - low > 2) {
    const mid = (low + high) / 2;
    if (greedy(words, size, tracking, mid).length === count) high = mid;
    else low = mid;
  }
  return greedy(words, size, tracking, high);
}

// `value` is a string (wrapped here) or an array of lines (broken by hand where the thought breaks).
function fit(value, { passes, tracking }, accept = () => true) {
  for (const { sizes, maxLines } of passes) {
    for (const size of sizes) {
      const lines = Array.isArray(value) ? value : balance(value, size, tracking, TEXT_WIDTH);
      if (lines.length > maxLines || lines.some((line) => width(line, size, tracking) > TEXT_WIDTH)) continue;
      if (accept(size, lines)) return { size, lines };
    }
  }
  throw new Error(`Social card text does not fit: ${JSON.stringify(value)}`);
}

// The tile from public/logo.svg at 72px (viewBox 64, so scale 1.125).
const mark = (top) => `<g transform="translate(${MARGIN} ${top}) scale(${MARK / 64})">
    <clipPath id="tile"><rect width="64" height="64" rx="14"/></clipPath>
    <g clip-path="url(#tile)">
      <rect width="64" height="64" fill="${COLOR.line}"/>
      <path d="M26 72V40A16 16 0 0 1 42 24H72" fill="none" stroke="${COLOR.ground}" stroke-width="18"/>
      <circle cx="26" cy="50" r="6.8" fill="#fff"/>
    </g>
  </g>`;

// A 150px road (outer radius 225, inner 75) entering from the bottom and leaving right, centerline dashed 28 on, 24 off.
const road = `<path d="M800 700V450A150 150 0 0 1 950 300H1300" fill="none" stroke="${COLOR.road}" stroke-width="150"/>
  <path d="M800 648V450" fill="none" stroke="${COLOR.line}" stroke-width="6" stroke-dasharray="28 24"/>
  <path d="M800 450A150 150 0 0 1 950 300H1300" fill="none" stroke="${COLOR.line}" stroke-width="6" stroke-dasharray="28 24" stroke-dashoffset="49.4"/>`;

export function layoutCard({ title, sub }) {
  const subSet = sub ? fit(sub, SUB) : null;
  const subHeight = subSet ? SUB_GAP + CAP_HEIGHT * subSet.size + (subSet.lines.length - 1) * subSet.size * SUB.lineHeight : 0;
  const block = (size, lines) => MARK + MARK_GAP + CAP_HEIGHT * size + (lines.length - 1) * size * TITLE.lineHeight + subHeight;
  const head = fit(title, TITLE, (size, lines) => block(size, lines) <= MAX_BLOCK);
  // Centered like the existing card, a touch above the midline.
  const top = Math.round((HEIGHT - block(head.size, head.lines)) / 2 - 8);
  const first = Math.round(top + MARK + MARK_GAP + CAP_HEIGHT * head.size);
  const pitch = Math.round(head.size * TITLE.lineHeight);
  const lastBaseline = first + (head.lines.length - 1) * pitch;
  const subFirst = Math.round(lastBaseline + SUB_GAP + (subSet ? CAP_HEIGHT * subSet.size : 0));
  const subPitch = subSet ? Math.round(subSet.size * SUB.lineHeight) : 0;
  return { top, head: { ...head, first, pitch }, sub: subSet && { ...subSet, first: subFirst, pitch: subPitch } };
}

export function cardSVG(content) {
  const { top, head, sub } = layoutCard(content);
  const lines = head.lines.map((line, i) => text(line, { x: MARGIN, y: head.first + i * head.pitch, size: head.size, tracking: TITLE.tracking, fill: COLOR.ink }));
  const subs = sub ? sub.lines.map((line, i) => text(line, { x: MARGIN, y: sub.first + i * sub.pitch, size: sub.size, tracking: SUB.tracking, fill: COLOR.sub })) : [];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}">
  <rect width="${WIDTH}" height="${HEIGHT}" fill="${COLOR.ground}"/>
  ${road}
  ${mark(top)}
  ${text('RydAR', { x: MARGIN + MARK + 20, y: top + 53, size: 48, tracking: -0.03, fill: COLOR.wordmark })}
  ${[...lines, ...subs].join('\n  ')}
</svg>`;
}

export const renderCard = (content) =>
  new Resvg(cardSVG(content), { ...resvgOptions, fitTo: { mode: 'width', value: WIDTH } }).render().asPng();

// What the image says, for og:image:alt and twitter:image:alt.
export function cardAlt({ title, sub }) {
  const flat = (value) => (Array.isArray(value) ? value.join(' ') : value).replace(/\.$/, '');
  return `RydAR: ${flat(title)}${sub ? `. ${flat(sub)}` : ''}. The RydAR logo beside a bending road.`;
}
