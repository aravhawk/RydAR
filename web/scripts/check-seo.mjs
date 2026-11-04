import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
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
  const canonical = html.match(/<link rel="canonical" href="([^"]+)"/g) || [];
  assert.equal(canonical.length, 1);
  assert(canonical[0].includes(`href="${site.origin}${page.path}"`), `${page.path}: canonical mismatch`);
  for (const [key, value] of [['og:title', title], ['og:description', description], ['og:url', `${site.origin}${page.path}`]]) {
    assert(html.includes(`property="${key}" content="`));
    const actual = decode(html.match(new RegExp(`<meta property="${key}" content="([^"]+)"`))[1]);
    assert.equal(actual, value);
  }
  const data = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1] || 'null');
  assert.equal(data['@context'], 'https://schema.org');
  const graph = data['@graph'];
  assert.equal(graph.find((node) => isType(node, 'WebSite')).name, 'RydAR');
  assert(graph.find((node) => isType(node, 'Organization')).logo.url, 'Organization needs a logo');
  const webPage = graph.find((node) => isType(node, 'WebPage'));
  assert.equal(webPage.url, `${site.origin}${page.path}`);
  assert.equal(webPage.name, title);
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
assert.equal(config.outputDirectory, 'public');
assert(!config.rewrites, 'Do not mask missing pages or API endpoints with a homepage rewrite');
console.log(`SEO checks passed: ${entries.length} crawlable pages (${generated.length} county pages), unique metadata, JSON-LD, FAQs, canonicals, links, anchors, assets, routes, sitemap, robots.txt, and llms.txt.`);
