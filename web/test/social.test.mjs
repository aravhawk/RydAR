import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { pages } from '../content/pages.mjs';
import { countyPages } from '../content/counties.mjs';
import { ICONS, renderIcon } from '../scripts/icons.mjs';
import { HEIGHT, WIDTH, cardAlt, layoutCard, renderCard } from '../scripts/og-card.mjs';

const cards = [...pages, ...countyPages()].filter((page) => page.card);
const size = (png) => [png.readUInt32BE(16), png.readUInt32BE(20)];

test('the generator reproduces the layout measured from the existing og-image.png', () => {
  // Measured from public/og-image.png: tile top 155, first baseline 355, 104px type on a 104px pitch.
  const { top, head } = layoutCard({ title: ['Safe', 'Driving.'] });
  assert.deepEqual([top, head.size, head.first, head.pitch], [155, 104, 355, 104]);
});

test('every page has a card, and every card fits above and below the road and the margins', () => {
  assert.equal(cards.length, pages.length + 75);
  for (const page of cards) {
    const { top, head, sub } = layoutCard(page.card);
    assert(head.lines.length <= 3 && head.size >= 72, `${page.path}: ${head.lines.length} lines at ${head.size}px`);
    const bottom = sub ? sub.first + (sub.lines.length - 1) * sub.pitch : head.first + (head.lines.length - 1) * head.pitch;
    assert(top >= 60 && bottom <= HEIGHT - 60, `${page.path}: block runs ${top} to ${bottom}`);
    // A headline that wraps to three lines should not leave a single word alone at the end.
    if (head.lines.length === 3) assert(head.lines[2].includes(' '), `${page.path}: orphaned last word`);
  }
});

test('a card renders as a 1200 by 630 PNG', () => {
  for (const content of [pages[0].card, { title: 'Independence County.', sub: '2,692 mapped curves' }]) {
    const png = renderCard(content);
    assert.equal(png.subarray(1, 4).toString(), 'PNG');
    assert.deepEqual(size(png), [WIDTH, HEIGHT]);
  }
});

test('card text that cannot fit fails the build instead of overflowing', () => {
  assert.throws(() => layoutCard({ title: 'Supercalifragilisticexpialidocious County, Arkansas, United States of America.' }), /does not fit/);
});

test('card copy and alt text follow the copy rules', () => {
  for (const page of cards) {
    const alt = cardAlt(page.card);
    assert.doesNotMatch(JSON.stringify(page.card) + alt, /\u2014/, `${page.path}: em dash`);
    assert(alt.startsWith('RydAR: ') && alt.length <= 420, `${page.path}: alt is ${alt.length} characters`);
  }
  assert.equal(cardAlt({ title: 'Pulaski County.', sub: '7,553 mapped curves' }), 'RydAR: Pulaski County. 7,553 mapped curves. The RydAR logo beside a bending road.');
  assert.equal(cardAlt({ title: 'What your drive shares.', sub: ['Very little.', 'Here is exactly what.'] }), 'RydAR: What your drive shares. Very little. Here is exactly what. The RydAR logo beside a bending road.');
});

test('manifest icons render at the sizes they declare', async () => {
  const logo = await readFile(fileURLToPath(new URL('../public/logo.svg', import.meta.url)), 'utf8');
  for (const [name, px, maskable] of ICONS) assert.deepEqual(size(renderIcon(logo, px, maskable)), [px, px], name);
});
