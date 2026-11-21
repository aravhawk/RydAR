import assert from 'node:assert/strict';
import { access, readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { home, pages, site } from '../content/pages.mjs';
import { countyPages } from '../content/counties.mjs';

const publicDir = fileURLToPath(new URL('../public/', import.meta.url));
const generated = countyPages();
const entries = [home, ...pages, ...generated];
const isType = (node, type) => [].concat(node['@type']).includes(type);
const knownPaths = new Set(entries.map((page) => page.path));
const decode = (value) => value.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
const titles = new Set();
const descriptions = new Set();
const links = new Map();
const htmlByPath = new Map();
const imageOwner = new Map();

for (const page of entries) {
  const html = await readFile(`${publicDir}${page.path === '/' ? 'index' : page.path.slice(1)}.html`, 'utf8');
  htmlByPath.set(page.path, html);
  assert.equal((html.match(/<h1\b/g) || []).length, 1, `${page.path}: exactly one H1`);
  assert.match(html, /<html lang="en">/);
  assert.doesNotMatch(html, /(?:name="robots"[^>]*content="[^"]*noindex|class="seo")/);
  const title = decode(html.match(/<title>(.*?)<\/title>/s)?.[1] || '');
  assert.equal(title, page.title);
  // Google truncates around 60 characters of title and 160 of description.
  assert(title.length <= 60, `${page.path}: title is ${title.length} characters`);
  assert(title.includes('RydAR'), `${page.path}: title should carry the brand`);
  assert(page.description.length <= 160, `${page.path}: description is ${page.description.length} characters`);
  assert(!titles.has(title), `Duplicate title: ${title}`);
  titles.add(title);
  const description = decode(html.match(/<meta name="description" content="([^"]+)"/)?.[1] || '');
  assert.equal(description, page.description);
  assert(!descriptions.has(description), `Duplicate description: ${page.path}`);
  descriptions.add(description);
  assert(html.includes(`<meta name="apple-itunes-app" content="app-id=${site.appStoreId}">`), `${page.path}: missing Smart App Banner`);
  assert(html.includes(site.appStore), `${page.path}: missing App Store link`);
  assert.doesNotMatch(html, /testflight/i, `${page.path}: TestFlight reference`);
  const canonical = html.match(/<link rel="canonical" href="([^"]+)"/g) || [];
  assert.equal(canonical.length, 1);
  assert(canonical[0].includes(`href="${site.origin}${page.path}"`), `${page.path}: canonical mismatch`);
  for (const [key, value] of [['og:title', title], ['og:description', description], ['og:url', `${site.origin}${page.path}`]]) {
    assert(html.includes(`property="${key}" content="`));
    const actual = decode(html.match(new RegExp(`<meta property="${key}" content="([^"]+)"`))[1]);
    assert.equal(actual, value);
  }
  // Social previews: every Open Graph and Twitter tag, and the image file those tags point at.
  const tag = (attr, key) => {
    const found = html.match(new RegExp(`<meta ${attr}="${key}" content="([^"]*)"`));
    assert(found, `${page.path}: missing ${key}`);
    return decode(found[1]);
  };
  assert.equal(tag('property', 'og:type'), 'website');
  assert.equal(tag('property', 'og:site_name'), 'RydAR');
  assert.equal(tag('property', 'og:locale'), 'en_US');
  assert.equal(tag('name', 'twitter:card'), 'summary_large_image');
  assert.equal(tag('name', 'twitter:title'), title);
  assert.equal(tag('name', 'twitter:description'), description);
  const image = tag('property', 'og:image');
  assert.equal(image, page.card ? `${site.origin}/og/${page.path.split('/').pop()}.png` : `${site.origin}/og-image.png`, `${page.path}: unexpected social image`);
  assert.equal(tag('name', 'twitter:image'), image);
  assert.equal(tag('property', 'og:image:type'), 'image/png');
  assert.equal(tag('property', 'og:image:width'), '1200');
  assert.equal(tag('property', 'og:image:height'), '630');
  const alt = tag('property', 'og:image:alt');
  assert(alt.length >= 20 && alt.length <= 420, `${page.path}: og:image:alt is ${alt.length} characters`);
  assert.equal(tag('name', 'twitter:image:alt'), alt);
  assert(!imageOwner.has(image) || image.endsWith('/og-image.png'), `${page.path}: shares its social image with ${imageOwner.get(image)}`);
  imageOwner.set(image, page.path);
  const png = await readFile(`${publicDir}${image.slice(site.origin.length + 1)}`);
  assert.equal(png.subarray(1, 4).toString(), 'PNG', `${image}: not a PNG`);
  assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], [1200, 630], `${image}: must be 1200x630`);
  assert(png.length < 300 * 1024, `${image}: ${png.length} bytes is heavy for a preview`);
  // Copy rules for everything a crawler or a feed shows.
  for (const text of [title, description, alt]) assert.doesNotMatch(text, /\u2014/, `${page.path}: no em dashes in metadata`);
  // Head tags that stand in for a framework's metadata API: icons, manifest, theme color, one language.
  for (const required of ['<link rel="icon" href="/favicon.ico"', '<link rel="icon" href="/logo.svg"', '<link rel="apple-touch-icon" href="/apple-touch-icon.png">', '<link rel="manifest" href="/manifest.webmanifest">', '<meta name="theme-color" content="#062e38">', '<meta name="viewport"']) {
    assert(html.includes(required), `${page.path}: missing ${required}`);
  }
  assert.doesNotMatch(html, /hreflang/, `${page.path}: the site is English only, so it has no hreflang`);
  const data = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1] || 'null');
  assert.equal(data['@context'], 'https://schema.org');
  const graph = data['@graph'];
  assert.equal(graph.find((node) => isType(node, 'WebSite')).name, 'RydAR');
  assert(graph.find((node) => isType(node, 'Organization')).logo.url, 'Organization needs a logo');
  const webPage = graph.find((node) => isType(node, 'WebPage'));
  assert.equal(webPage.url, `${site.origin}${page.path}`);
  assert.equal(webPage.name, title);
  assert.equal(webPage.primaryImageOfPage.url, image, `${page.path}: JSON-LD image must match og:image`);
  if (page.path !== '/') {
    const crumbs = graph.find((node) => isType(node, 'BreadcrumbList')).itemListElement;
    assert.equal(crumbs.at(-1).item, webPage.url);
    assert.equal(crumbs.length, 2 + (page.parents?.length || 0), `${page.path}: breadcrumb depth`);
    assert(html.includes('aria-label="Breadcrumb"'));
    // Information pages should work without the map runtime or large data downloads.
    const markup = html.replace(/<script type="application\/ld\+json">[\s\S]*?<\/script>/, '');
    assert.doesNotMatch(markup, /maplibre|curves-arkansas-\d\.geojson/, `${page.path}: loads the map runtime`);
    if (!page.script) assert.doesNotMatch(html, /<script(?! type="application\/ld\+json")/, `${page.path}: unexpected script`);
  }
  // Structured FAQs must match questions a visitor can actually read on the page.
  const faq = page.blocks?.find((item) => item.type === 'faq');
  if (faq) {
    assert(isType(webPage, 'FAQPage'), `${page.path}: FAQ block without FAQPage data`);
    assert.equal(webPage.mainEntity.length, faq.items.length);
    for (const [question] of faq.items) assert(html.includes(`<summary>${question}`), `${page.path}: FAQ "${question}" not visible`);
  } else {
    assert(!isType(webPage, 'FAQPage'), `${page.path}: FAQPage data without visible questions`);
  }
  for (const node of graph) {
    assert(!node.aggregateRating && !node.review, 'Do not invent ratings or reviews');
  }
  const destinations = [];
  for (const [, attr, raw] of html.matchAll(/\b(href|src)="([^"]+)"/g)) {
    const value = decode(raw);
    if (/^(https?:|data:)/.test(value)) continue;
    const target = new URL(value, `${site.origin}${page.path}`);
    if (knownPaths.has(target.pathname)) {
      if (attr === 'href') destinations.push(target.pathname);
    } else {
      await access(`${publicDir}${target.pathname}`);
    }
    if (target.hash) {
      const targetHTML = htmlByPath.get(target.pathname) || await readFile(`${publicDir}${target.pathname === '/' ? 'index' : target.pathname.slice(1)}.html`, 'utf8');
      assert(targetHTML.includes(`id="${target.hash.slice(1)}"`), `${page.path}: broken anchor ${value}`);
    }
  }
  links.set(page.path, destinations);
}

// All indexable pages must be discoverable through ordinary HTML links from home.
const reached = new Set();
const queue = ['/'];
while (queue.length) {
  const path = queue.shift();
  if (reached.has(path)) continue;
  reached.add(path);
  queue.push(...links.get(path));
}
assert.deepEqual(reached, knownPaths);
const sitemap = await readFile(`${publicDir}sitemap.xml`, 'utf8');
assert(sitemap.includes('xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'));
for (const [, date] of sitemap.matchAll(/<lastmod>(.*?)<\/lastmod>/g)) {
  assert(/^\d{4}-\d{2}-\d{2}$/.test(date) && date <= new Date().toISOString().slice(0, 10), `Bad sitemap lastmod: ${date}`);
}
assert.deepEqual(new Set([...sitemap.matchAll(/<loc>(.*?)<\/loc>/g)].map((match) => match[1])), new Set(entries.map((page) => `${site.origin}${page.path}`)));
const robots = await readFile(`${publicDir}robots.txt`, 'utf8');
assert(robots.includes(`Sitemap: ${site.origin}/sitemap.xml`));
assert.doesNotMatch(robots, /^Disallow:\s*\/\s*$/m);
const config = JSON.parse(await readFile(new URL('../vercel.json', import.meta.url), 'utf8'));
assert.equal(config.framework, null, 'Use static routing rather than a framework SPA fallback');
assert(config.routes.some((route) => route.handle === 'filesystem'));
assert.deepEqual(config.routes.at(-1), { src: '^/.*$', dest: '/404.html', status: 404 });
const route = config.routes.find((item) => item.dest === '/$1.html');
for (const page of [...pages, ...generated]) {
  assert(new RegExp(route.src).test(page.path), `${page.path}: missing extensionless route`);
  await access(`${publicDir}${page.path.slice(1)}.html`);
}
assert(!new RegExp(route.src).test('/arkansas-curve-map/nowhere-county'), 'Unknown county pages must reach the 404');
assert((await readFile(`${publicDir}llms.txt`, 'utf8')).startsWith('# RydAR'));
// The social cards on disk are exactly the ones pages point at; none are left over from removed pages.
assert.deepEqual(
  (await readdir(`${publicDir}og`)).sort(),
  entries.filter((page) => page.card).map((page) => `${page.path.split('/').pop()}.png`).sort(),
  'public/og holds a card for every page that has one, and nothing else',
);
// The web app manifest: installable (192 and 512 PNGs, one maskable) and every icon real.
const manifest = JSON.parse(await readFile(`${publicDir}manifest.webmanifest`, 'utf8'));
assert.equal(manifest.theme_color, '#062e38');
assert.equal(manifest.start_url, '/');
assert.equal(manifest.lang, 'en-US');
assert(manifest.id && manifest.scope, 'manifest needs an id and a scope');
for (const icon of manifest.icons) {
  const file = await readFile(`${publicDir}${icon.src.slice(1)}`);
  if (icon.type === 'image/png') {
    const [w, h] = [file.readUInt32BE(16), file.readUInt32BE(20)];
    assert.equal(`${w}x${h}`, icon.sizes, `${icon.src}: declared ${icon.sizes}`);
  }
}
for (const size of ['192x192', '512x512']) assert(manifest.icons.some((icon) => icon.sizes === size && icon.type === 'image/png' && (icon.purpose || 'any') === 'any'), `manifest needs a ${size} PNG icon`);
assert(manifest.icons.some((icon) => icon.purpose === 'maskable' && icon.type === 'image/png'), 'manifest needs a maskable icon');
assert((await readFile(`${publicDir}icons/icon-512.png`)).readUInt32BE(16) === 512);
// A missing page must not be indexed or claim a canonical address.
const notFound = await readFile(`${publicDir}404.html`, 'utf8');
assert.match(notFound, /<meta name="robots" content="noindex">/);
assert.doesNotMatch(notFound, /rel="canonical"/);
assert.equal(config.outputDirectory, 'public');
assert(!config.rewrites, 'Do not mask missing pages or API endpoints with a homepage rewrite');
console.log(`SEO checks passed: ${entries.length} crawlable pages (${generated.length} county pages), unique metadata, Open Graph and Twitter cards, social images, JSON-LD, FAQs, canonicals, icons, manifest, links, anchors, assets, routes, sitemap, robots.txt, and llms.txt.`);
