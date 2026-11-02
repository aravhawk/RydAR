import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { home, pages, site } from '../content/pages.mjs';

const publicDir = fileURLToPath(new URL('../public/', import.meta.url));
const escape = (value) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const url = (path) => `${site.origin}${path}`;
const ref = (id) => ({ '@id': url(`/#${id}`) });

function metadata(page) {
  const graph = [
    {
      '@type': 'Organization', ...ref('org'), name: site.name, url: url('/'),
      logo: url('/apple-touch-icon.png'), sameAs: [site.source],
    },
    {
      '@type': 'WebSite', ...ref('website'), name: site.name,
      alternateName: ['RydAR: Safe Driving', 'RydAR Arkansas'], url: url('/'),
      description: home.description, inLanguage: 'en-US', publisher: ref('org'),
    },
    {
      '@type': 'WebPage', '@id': `${url(page.path)}#webpage`, url: url(page.path),
      name: page.title, description: page.description, inLanguage: 'en-US',
      isPartOf: ref('website'), about: ref(page.path === '/iphone-app' ? 'app' : 'org'),
      primaryImageOfPage: { '@type': 'ImageObject', url: url('/og-image.png') },
      ...(page.path === '/' ? { mainEntity: ref('map') } : { breadcrumb: { '@id': `${url(page.path)}#breadcrumb` } }),
    },
  ];
  if (page.path !== '/') {
    graph.push({
      '@type': 'BreadcrumbList', '@id': `${url(page.path)}#breadcrumb`,
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: site.name, item: url('/') },
        { '@type': 'ListItem', position: 2, name: page.label, item: url(page.path) },
      ],
    });
  }
  if (page.path === '/' || page.path === '/arkansas-curve-map') {
    graph.push({
      '@type': 'WebApplication', ...ref('map'), name: 'RydAR Arkansas Curve Map',
      url: url('/'), applicationCategory: 'NavigationApplication', operatingSystem: 'Any',
      browserRequirements: 'Requires JavaScript', isAccessibleForFree: true,
      description: 'Free map of tight bends on Arkansas county roads, with road surfaces and computed suggested speed ranges.',
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
      image: url('/og-image.png'), publisher: ref('org'), isPartOf: ref('website'),
    });
  }
  if (page.path === '/' || page.path === '/iphone-app') {
    graph.push({
      '@type': 'MobileApplication', ...ref('app'), name: site.name,
      url: url('/iphone-app'), description: 'An iPhone app for spoken curve warnings on Arkansas roads, available as a free TestFlight beta.',
      applicationCategory: 'NavigationApplication', operatingSystem: 'iOS',
      installUrl: site.beta, image: url('/og-image.png'), publisher: ref('org'),
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
    });
  }
  return `<!-- seo:head:start -->
  <title>${escape(page.title)}</title>
  <meta name="description" content="${escape(page.description)}">
  <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">
  <meta name="application-name" content="RydAR">
  <meta name="apple-mobile-web-app-title" content="RydAR">
  <meta name="theme-color" content="#062e38">
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

const block = (item) => {
  if (item.type === 'steps') {
    return `<ol class="card steps">${item.items.map(([title, text]) => `<li><div><h2>${title}</h2><p>${text}</p></div></li>`).join('')}</ol>`;
  }
  if (item.type === 'tiles') {
    return `<div class="tiles" data-count="${item.items.length}">${item.items.map(([name, title, text]) => `<section class="card tile">${icon(name)}<h2>${title}</h2><p>${text}</p></section>`).join('')}</div>`;
  }
  if (item.type === 'formula') {
    return `<section class="card formula"><p class="equation" aria-label="V equals the square root of 15 times R times e plus f">${item.formula}</p><ul>${item.terms.map((term) => `<li>${term}</li>`).join('')}</ul><p>${item.text}</p></section>`;
  }
  return `<p class="note">${item.text}</p>`;
};

const footerLinks = (current) => [['/', 'Map'], ...pages.map((page) => [page.path, page.label])]
  .filter(([path]) => path !== current)
  .map(([path, label]) => `<a href="${path}">${label}</a>`)
  .concat(`<a href="${site.source}">GitHub</a>`)
  .join('');

const shell = ({ head, current, crumb, heading, intro, action, blocks }) => `<!DOCTYPE html>
<!-- Generated by scripts/build-pages.mjs from content/pages.mjs. -->
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
      ${crumb ? `<nav class="crumb" aria-label="Breadcrumb"><a href="/">RydAR</a><span aria-hidden="true">/</span><span aria-current="page">${crumb}</span></nav>` : ''}
      <h1>${heading}</h1>
      <p class="lede">${intro}</p>
      ${action ? `<a class="action" href="${action[1]}">${action[0]}${arrow}</a>` : ''}
    </header>
    ${blocks.map(block).join('\n    ')}
  </main>
  <footer><nav aria-label="Footer">${footerLinks(current)}</nav></footer>
</body>
</html>
`;

const write = (name, html) => writeFile(`${publicDir}${name}`, html.replace(/[ \t]+$/gm, ''));

for (const page of pages) {
  await write(`${page.path.slice(1)}.html`, shell({
    head: metadata(page), current: page.path, crumb: page.label,
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

// No invented modification dates: regenerate from the actual page list.
await writeFile(`${publicDir}sitemap.xml`, `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${[home, ...pages].map((page) => `  <url><loc>${url(page.path)}</loc></url>`).join('\n')}
</urlset>
`);
console.log(`Built ${pages.length} information pages, homepage metadata, and sitemap.`);
