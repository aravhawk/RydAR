import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { home, pages, site } from '../content/pages.mjs';
import { countyPages, counties, statewide, FRICTION } from '../content/counties.mjs';

const publicDir = fileURLToPath(new URL('../public/', import.meta.url));
const escape = (value) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const plain = (html) => html.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
const url = (path) => `${site.origin}${path}`;
const ref = (id) => ({ '@id': url(`/#${id}`) });
const logo = { '@type': 'ImageObject', url: url('/apple-touch-icon.png'), width: 180, height: 180 };
const ogImage = { '@type': 'ImageObject', url: url('/og-image.png'), width: 1200, height: 630 };
const arkansas = { '@type': 'State', name: 'Arkansas', containedInPlace: { '@type': 'Country', name: 'United States' } };
const countyPlace = (name) => ({ '@type': 'AdministrativeArea', name: `${name} County, Arkansas`, containedInPlace: arkansas });

function metadata(page) {
  const faq = page.blocks?.find((item) => item.type === 'faq');
  const graph = [
    {
      '@type': 'Organization', ...ref('org'), name: site.name, alternateName: site.alternateNames,
      url: url('/'), logo, image: logo, slogan: site.slogan, sameAs: [site.source, site.appStore],
      description: 'RydAR makes a free Arkansas curve map and an iPhone app that speaks a suggested speed before tight curves.',
    },
    {
      '@type': 'WebSite', ...ref('website'), name: site.name, alternateName: site.alternateNames,
      url: url('/'), description: home.description, inLanguage: 'en-US', publisher: ref('org'),
    },
    {
      '@type': faq ? ['WebPage', 'FAQPage'] : 'WebPage', '@id': `${url(page.path)}#webpage`, url: url(page.path),
      name: page.title, description: page.description, inLanguage: 'en-US',
      isPartOf: ref('website'), publisher: ref('org'),
      about: page.county ? countyPlace(page.county) : ref(page.path === '/iphone-app' ? 'app' : 'org'),
      primaryImageOfPage: ogImage,
      ...(page.path === '/' ? { mainEntity: ref('map') } : { breadcrumb: { '@id': `${url(page.path)}#breadcrumb` } }),
      ...(faq ? { mainEntity: faq.items.map(([question, answer]) => ({
        '@type': 'Question', name: question, acceptedAnswer: { '@type': 'Answer', text: plain(answer) },
      })) } : {}),
    },
  ];
  if (page.path !== '/') {
    const trail = [['/', site.name], ...(page.parents || []), [page.path, page.label]];
    graph.push({
      '@type': 'BreadcrumbList', '@id': `${url(page.path)}#breadcrumb`,
      itemListElement: trail.map(([path, name], index) => ({ '@type': 'ListItem', position: index + 1, name, item: url(path) })),
    });
  }
  if (page.path === '/' || page.path === '/arkansas-curve-map') {
    graph.push({
      '@type': 'WebApplication', ...ref('map'), name: 'RydAR Arkansas Curve Map',
      url: url('/'), applicationCategory: 'TravelApplication', operatingSystem: 'Any',
      browserRequirements: 'Requires JavaScript', isAccessibleForFree: true,
      description: `Free map of ${statewide.total.toLocaleString('en-US')} curves on Arkansas roads in all 75 counties, with road surfaces and a suggested speed for each.`,
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
      image: ogImage, publisher: ref('org'), isPartOf: ref('website'), spatialCoverage: arkansas,
    });
  }
  if (page.path === '/' || page.path === '/iphone-app') {
    graph.push({
      '@type': 'MobileApplication', ...ref('app'), name: site.name, alternateName: 'RydAR: Safe Driving',
      url: url('/iphone-app'), description: 'An iPhone app that speaks a suggested speed before tight curves on Arkansas roads, available as a free download on the App Store.',
      applicationCategory: 'TravelApplication', operatingSystem: 'iOS 17.0 or later', isAccessibleForFree: true,
      contentRating: '4+', datePublished: '2026-11-11', sameAs: site.appStore, countriesSupported: 'US',
      featureList: ['Spoken curve warnings', 'Suggested curve speeds', 'Built-in Arkansas curve database', 'Teen driver mode', 'Optional camera road-surface check'],
      installUrl: site.appStore, downloadUrl: site.appStore, image: ogImage, publisher: ref('org'),
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
    });
  }
  if (page.dataset) {
    graph.push({
      '@type': 'Dataset', '@id': url('/arkansas-curve-map#dataset'), name: 'Arkansas road curves',
      description: `Every bend tighter than 600 ft in radius on Arkansas roads, ${statewide.total.toLocaleString('en-US')} in all, measured from Arkansas GIS Office road centerlines. Each curve has its county, road name, surface, radius in feet, and turn angle in degrees.`,
      url: url('/arkansas-curve-map'), creator: ref('org'), publisher: ref('org'), isAccessibleForFree: true,
      isBasedOn: 'https://gis.arkansas.gov/arcgis/rest/services/FEATURESERVICES/Transportation/MapServer/18',
      spatialCoverage: arkansas, keywords: ['Arkansas', 'road curves', 'horizontal curves', 'curve radius', 'road safety'],
      variableMeasured: ['radius_ft', 'deflection_deg', 'surface'],
      distribution: [1, 2, 3, 4].map((n) => ({ '@type': 'DataDownload', encodingFormat: 'application/geo+json', contentUrl: url(`/data/curves-arkansas-${n}.geojson`) })),
    });
  }
  if (page.path === '/curve-speed-calculator') {
    graph.push({
      '@type': 'WebApplication', '@id': `${url(page.path)}#calculator`, name: 'RydAR Curve Speed Calculator',
      url: url(page.path), applicationCategory: 'UtilitiesApplication', operatingSystem: 'Any', isAccessibleForFree: true,
      description: 'Suggested safe speed for a road curve from its radius and surface.',
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' }, publisher: ref('org'),
    });
  }
  return `<!-- seo:head:start -->
  <title>${escape(page.title)}</title>
  <meta name="description" content="${escape(page.description)}">
  <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">
  <meta name="application-name" content="RydAR">
  <meta name="apple-mobile-web-app-title" content="RydAR">
  <meta name="theme-color" content="#062e38">
  <meta name="apple-itunes-app" content="app-id=${site.appStoreId}">
  <meta name="geo.region" content="US-AR">
  <link rel="canonical" href="${url(page.path)}">
  <link rel="manifest" href="/manifest.webmanifest">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="RydAR">
  <meta property="og:locale" content="en_US">
  <meta property="og:title" content="${escape(page.title)}">
  <meta property="og:description" content="${escape(page.description)}">
  <meta property="og:url" content="${url(page.path)}">
  <meta property="og:image" content="${url('/og-image.png')}">
  <meta property="og:image:type" content="image/png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="RydAR: Safe Driving, with the RydAR logo beside a bending road.">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escape(page.title)}">
  <meta name="twitter:description" content="${escape(page.description)}">
  <meta name="twitter:image" content="${url('/og-image.png')}">
  <meta name="twitter:image:alt" content="RydAR: Safe Driving, with the RydAR logo beside a bending road.">
  <script type="application/ld+json">${JSON.stringify({ '@context': 'https://schema.org', '@graph': graph }).replaceAll('<', '\\u003c')}</script>
  <!-- seo:head:end -->`;
}

const icons = {
  pin: '<path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11z"/><circle cx="12" cy="10" r="2.5"/>',
  gauge: '<path d="M4 17a8 8 0 1 1 16 0"/><path d="m12 17 4-5"/>',
  speaker: '<path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>',
  database: '<ellipse cx="12" cy="6" rx="7" ry="3"/><path d="M5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6M5 12c0 1.7 3.1 3 7 3s7-1.3 7-3"/>',
  wheel: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2"/><path d="M3 12h7M14 12h7M12 14v7"/>',
  person: '<circle cx="12" cy="8" r="4"/><path d="M4.5 21c1-4 4-6 7.5-6s6.5 2 7.5 6"/>',
  camera: '<path d="M4 8h3l1.5-2h7L17 8h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
  share: '<path d="M12 15V4M8 8l4-4 4 4"/><path d="M5 14v6h14v-6"/>',
};
const icon = (name) => `<span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg></span>`;
const arrow = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 17 17 7M8 7h9v9"/></svg>';
const chevron = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>';

// The calculator works out the default radius at build time, so the page reads right before (or without) the script.
const calcScript = `<script>
(() => {
  const form = document.getElementById('calc');
  const speed = document.getElementById('calc-speed');
  const sub = document.getElementById('calc-sub');
  const friction = ${JSON.stringify(FRICTION)};
  const mph = (r, e, f) => Math.sqrt(Math.max(0, 15 * r * (e + f)));
  const update = () => {
    const value = Number(form.radius.value);
    const feet = form.unit.value === 'm' ? value * 3.28084 : value;
    if (!Number.isFinite(feet) || feet <= 0) {
      speed.textContent = '–';
      sub.textContent = 'Enter a radius above zero.';
      return;
    }
    const f = friction[form.surface.value];
    const low = mph(feet, -0.02, f);
    const high = mph(feet, 0.02, f);
    speed.textContent = Math.floor(low) + '–' + Math.floor(high);
    sub.textContent = 'About ' + Math.floor(low * 1.609344) + '–' + Math.floor(high * 1.609344) + ' km/h. RydAR would say “Slow to ' + Math.floor(low) + ' mph for the curve ahead.”';
  };
  form.addEventListener('input', update);
  form.addEventListener('change', update);
  form.addEventListener('submit', (event) => { event.preventDefault(); update(); });
  update();
})();
</script>`;

function calculator({ radius }) {
  const low = Math.sqrt(15 * radius * (FRICTION.paved - 0.02));
  const high = Math.sqrt(15 * radius * (FRICTION.paved + 0.02));
  return `<section class="card calc" aria-label="Curve speed calculator">
      <form id="calc" class="calc-form">
        <div class="calc-field">
          <label for="radius">Curve radius</label>
          <div class="calc-input">
            <input id="radius" name="radius" type="number" inputmode="decimal" min="1" max="100000" step="any" value="${radius}">
            <select id="unit" name="unit" aria-label="Radius unit"><option value="ft" selected>ft</option><option value="m">m</option></select>
          </div>
        </div>
        <fieldset class="calc-field">
          <legend>Road surface</legend>
          <div class="segmented">
            <label><input type="radio" name="surface" value="paved" checked><span>Paved</span></label>
            <label><input type="radio" name="surface" value="unpaved"><span>Unpaved</span></label>
          </div>
        </fieldset>
      </form>
      <output class="calc-result" for="radius unit" aria-live="polite"><span id="calc-speed">${Math.floor(low)}–${Math.floor(high)}</span><span class="calc-unit">mph</span></output>
      <p class="calc-sub" id="calc-sub">About ${Math.floor(low * 1.609344)}–${Math.floor(high * 1.609344)} km/h. RydAR would say “Slow to ${Math.floor(low)} mph for the curve ahead.”</p>
    </section>
    ${calcScript}`;
}

const block = (item) => {
  if (item.type === 'steps') {
    return `<ol class="card steps">${item.items.map(([title, text]) => `<li><div><h2>${title}</h2><p>${text}</p></div></li>`).join('')}</ol>`;
  }
  if (item.type === 'tiles') {
    return `<div class="tiles" data-count="${item.items.length}">${item.items.map(([name, title, text]) => `<section class="card tile">${icon(name)}<h2>${title}</h2><p>${text}</p></section>`).join('')}</div>`;
  }
  if (item.type === 'stats') {
    return `<dl class="stats">${item.items.map(([value, label]) => `<div class="card stat"><dt>${label}</dt><dd>${value}</dd></div>`).join('')}</dl>`;
  }
  if (item.type === 'table') {
    const cell = (index) => (item.numeric?.includes(index) ? ' class="num"' : '');
    return `<section class="card data">
      <h2>${item.title}</h2>${item.text ? `<p>${item.text}</p>` : ''}
      <div class="scroll" role="region" aria-label="${escape(item.title)}" tabindex="0"><table>
        <thead><tr>${item.head.map((head, i) => `<th scope="col"${cell(i)}>${head}</th>`).join('')}</tr></thead>
        <tbody>${item.rows.map((row) => `<tr>${row.map((value, i) => (i === 0 ? `<th scope="row"${cell(i)}>${value}</th>` : `<td${cell(i)}>${value}</td>`)).join('')}</tr>`).join('')}</tbody>
      </table></div>
    </section>`;
  }
  if (item.type === 'links') {
    return `<section class="card links"${item.id ? ` id="${item.id}"` : ''}>
      <h2>${item.title}</h2>
      <ul class="link-grid${item.columns ? ' wide' : ''}">${item.items.map(([href, label, meta]) => `<li><a href="${href}"><span>${label}</span><small>${meta}</small></a></li>`).join('')}</ul>
    </section>`;
  }
  if (item.type === 'faq') {
    return `<section class="card faq">
      <h2>${item.title || 'Questions'}</h2>
      ${item.items.map(([question, answer]) => `<details><summary>${question}${chevron}</summary><p>${answer}</p></details>`).join('')}
    </section>`;
  }
  if (item.type === 'calculator') return calculator(item);
  if (item.type === 'formula') {
    return `<section class="card formula"><p class="equation" aria-label="V equals the square root of 15 times R times e plus f">${item.formula}</p><ul>${item.terms.map((term) => `<li>${term}</li>`).join('')}</ul><p>${item.text}</p></section>`;
  }
  if (item.type === 'policy') {
    const part = (entry) => typeof entry === 'string'
      ? `<p>${entry}</p>`
      : `<ul>${entry.list.map((line) => `<li>${line}</li>`).join('')}</ul>`;
    return `<article class="card policy">${item.sections.map(([title, entries]) => `<section><h2>${title}</h2>${entries.map(part).join('')}</section>`).join('')}<p class="updated">Last updated ${item.updated}.</p></article>`;
  }
  return `<p class="note">${item.text}</p>`;
};

const footerLinks = (current) => [['/', 'Map'], ...pages.map((page) => [page.path, page.label])]
  .filter(([path]) => path !== current)
  .map(([path, label]) => `<a href="${path}">${label}</a>`)
  .concat(`<a href="${site.appStore}" rel="noopener">RydAR on the App Store</a>`, `<a href="${site.source}">GitHub</a>`)
  .join('');

const shell = ({ head, current, parents = [], crumb, heading, intro, action, blocks }) => `<!DOCTYPE html>
<!-- Generated by scripts/build-pages.mjs from content/pages.mjs and content/counties.mjs. -->
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  ${head}
  <link rel="icon" href="/favicon.ico" sizes="32x32">
  <link rel="icon" href="/logo.svg" type="image/svg+xml">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <link rel="stylesheet" href="/information.css">
</head>
<body>
  <header class="top"><a class="wordmark" href="/" aria-label="RydAR home"><img src="/logo.svg" width="40" height="40" alt="">RydAR</a></header>
  <main>
    <header class="hero">
      ${crumb ? `<nav class="crumb" aria-label="Breadcrumb"><a href="/">RydAR</a>${parents.map(([path, label]) => `<span aria-hidden="true">/</span><a href="${path}">${label}</a>`).join('')}<span aria-hidden="true">/</span><span aria-current="page">${crumb}</span></nav>` : ''}
      <h1>${heading}</h1>
      <p class="lede">${intro}</p>
      ${action ? `<a class="action" href="${action[1]}">${action[0]}${arrow}</a>` : ''}
    </header>
    ${blocks.map(block).join('\n    ')}
  </main>
  <footer>
    <nav aria-label="Footer">${footerLinks(current)}</nav>
    <p class="brandline"><strong>RydAR</strong> · Curve warnings for Arkansas roads</p>
  </footer>
</body>
</html>
`;

const write = (name, html) => writeFile(`${publicDir}${name}`, html.replace(/[ \t]+$/gm, ''));
const generated = countyPages();
const indexed = [...pages, ...generated];

await mkdir(`${publicDir}arkansas-curve-map`, { recursive: true });
for (const page of indexed) {
  await write(`${page.path.slice(1)}.html`, shell({
    head: metadata(page), current: page.path, parents: page.parents, crumb: page.label,
    heading: page.heading, intro: page.intro, action: page.action, blocks: page.blocks,
  }));
}

await write('404.html', shell({
  head: '<title>Page Not Found | RydAR</title>\n  <meta name="robots" content="noindex">',
  current: null, heading: 'Page not found.', intro: 'That address doesn’t lead anywhere.',
  action: ['Open the map', '/'], blocks: [],
}));

const homePath = `${publicDir}index.html`;
const original = await readFile(homePath, 'utf8');
if (!original.includes('<!-- seo:head:start -->') || !original.includes('<!-- seo:head:end -->')) {
  throw new Error('Homepage is missing its metadata generation markers');
}
await writeFile(homePath, original.replace(/<!-- seo:head:start -->[\s\S]*?<!-- seo:head:end -->/, metadata(home)));

// Modification dates come from real history: the last commit that touched a page (and, for the
// map pages, the curve data), or today for files with uncommitted changes. Where git history is
// unavailable (a source upload or a shallow clone), keep the dates already in the committed sitemap.
const git = (...args) => execFileSync('git', args, { cwd: publicDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
let history = true;
try { history = git('rev-parse', '--is-shallow-repository') === 'false'; } catch { history = false; }
const previous = new Map();
try {
  for (const [, loc, date] of (await readFile(`${publicDir}sitemap.xml`, 'utf8')).matchAll(/<loc>(.*?)<\/loc>(?:<lastmod>(.*?)<\/lastmod>)?/g)) if (date) previous.set(loc, date);
} catch {}
const today = new Date().toISOString().slice(0, 10);
const pageFile = (page) => `${page.path === '/' ? 'index' : page.path.slice(1)}.html`;
const lastmod = (page) => {
  if (!history) return previous.get(url(page.path));
  const files = [pageFile(page), ...(page.path === '/' || page.path === '/arkansas-curve-map' ? ['data'] : [])];
  try {
    if (git('status', '--porcelain', '--', ...files)) return today;
    return git('log', '-1', '--format=%cs', '--', ...files) || previous.get(url(page.path));
  } catch { return previous.get(url(page.path)); }
};
const entry = (page) => { const date = lastmod(page); return `  <url><loc>${url(page.path)}</loc>${date ? `<lastmod>${date}</lastmod>` : ''}</url>`; };
await writeFile(`${publicDir}sitemap.xml`, `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${[home, ...indexed].map(entry).join('\n')}
</urlset>
`);

// A plain-text summary for AI search and answer engines (llmstxt.org).
await writeFile(`${publicDir}llms.txt`, `# RydAR

> RydAR (rydar.org) is a free map of ${statewide.total.toLocaleString('en-US')} curves on Arkansas roads in all ${statewide.counties} counties, and an iPhone app that speaks a suggested speed before tight curves ("Slow to 25 mph for the curve ahead."). The suggested speed comes from V = √(15 · R · (e + f)) and is separate from posted speed limits.

- Map: works in any browser, no account. Pick a county, search a road, tap a curve for its radius, turn angle, and suggested speed.
- iPhone app: free on the App Store (${site.appStore}). The curve database is built in. Driver mode and Teen driver mode.
- Source code: ${site.source}

## Pages

${[home, ...pages].map((page) => `- [${page.title}](${url(page.path)}): ${page.description}`).join('\n')}

## Curvy roads by county

${counties.map((county) => `- [${county.name} County](${url(county.path)}): ${county.total.toLocaleString('en-US')} curves`).join('\n')}
`);
console.log(`Built ${pages.length} information pages, ${generated.length} county pages, homepage metadata, sitemap, and llms.txt.`);
