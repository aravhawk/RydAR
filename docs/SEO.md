# RydAR search visibility

## What this change addresses

The production audit found an indexable homepage with working HTTPS and www redirects, but only one content URL. Its explanatory text used a one-pixel clipped `.seo` section. Its sitemap also declared `http://www.w3.org/2000/sitemap/0.9`, rather than the sitemap protocol namespace. These findings do not establish why Google ranks the site where it does; Search Console is needed to diagnose indexing and search performance.

The implementation adds visible homepage copy, four static information pages, ordinary HTML links between them, unique titles and descriptions, canonical URLs, consistent RydAR entity identifiers, WebSite/WebPage/application/breadcrumb structured data, and a sitemap using the correct namespace. It removes the obsolete keywords meta tag. Google does not use that tag for web ranking.

The existing interactive map stays on `/`. Information pages need no JavaScript, account, web fonts, map libraries, or curve downloads. The map's four curve files total roughly 72 MB before HTTP compression; production already serves Brotli. If mobile performance remains poor, profile map initialization and consider loading curve data by county. Do not claim a Core Web Vitals improvement without field measurements.

## Publishing

Pushes to `main` trigger the existing production deployment, with the Vercel project root set to `web/`. Publish through that Git integration; direct Vercel CLI access is not required. Use the existing RydAR project rather than creating a second project or moving the domain.

From `web/`:

```sh
npm ci
npm run build
npm run check
npm run check:seo
```

`content/pages.mjs` contains the page copy and metadata. `scripts/build-pages.mjs` generates the four information HTML files, the marked metadata block in `public/index.html`, and `public/sitemap.xml`. Generated output is checked in so it is reviewable. Edit the content source, not the generated information pages. The Vercel build runs generation. Explicit static routes serve the extensionless canonical paths and redirect `.html` and trailing-slash variants. A filesystem check preserves static assets and API functions, followed by an explicit HTTP 404 fallback for missing paths. `/index` and `/index.html` redirect home. API responses get `X-Robots-Tag: noindex`; API source and endpoints are unchanged.

After deploying, verify these URLs return 200 and the expected HTML metadata:

- `https://rydar.org/`
- `https://rydar.org/arkansas-curve-map`
- `https://rydar.org/iphone-app`
- `https://rydar.org/how-it-works`
- `https://rydar.org/data-and-privacy`
- `https://rydar.org/robots.txt`
- `https://rydar.org/sitemap.xml`

Also verify `/iphone-app.html` redirects to `/iphone-app`, `/index.html` redirects to `/`, `www.rydar.org` redirects to the apex, `/api/health` still returns JSON, and an invented path still returns 404. Do not add a catch-all homepage rewrite: it creates soft 404s.

## Search Console: do this after publishing

1. Open [Google Search Console](https://search.google.com/search-console). Select or create a **Domain property for `rydar.org`**. If it is new, use the DNS TXT value Google supplies to verify ownership. Do not put an invented verification token in the source.
2. Submit `https://rydar.org/sitemap.xml` in Sitemaps. Confirm Google reads the new five-URL sitemap without a namespace or fetch error.
3. Inspect `https://rydar.org/`. Run **Test live URL**. Check that indexing is allowed, the fetched page has the new content, and the declared canonical is the apex homepage. Request indexing. Repeat for the app and map guide pages. A request does not guarantee indexing.
4. Check **Page indexing**, **Manual actions**, **Security issues**, and **Removals**. For an excluded page, read the actual exclusion reason before changing code. If Google chooses another canonical, inspect duplicates and redirects.
5. Run the [Rich Results Test](https://search.google.com/test/rich-results) on published pages and review the breadcrumb markup. Organization and WebSite markup can help identify the brand, but does not guarantee a special result. Application markup has no fabricated reviews or ratings; it may not qualify for an app rich result without additional genuine eligibility data.
6. Review mobile Core Web Vitals in Search Console and [PageSpeed Insights](https://pagespeed.web.dev/). The information pages are light; measure the interactive map separately.

No Search Console property, DNS access, or search analytics was available during this implementation. A direct automated Google search returned a JavaScript challenge, so no independent ranking baseline was recorded.

## Search intent and useful landing pages

| Intent | Queries to measure | Landing page |
| --- | --- | --- |
| Brand | rydar, rydar app, rydar arkansas | `/` |
| Explore roads | Arkansas curve map, Arkansas county road curves | `/arkansas-curve-map` and `/` |
| App | iPhone curve warning app, Arkansas curve warning app | `/iphone-app` |
| Understand advisories | suggested curve speeds, how curve speeds are calculated | `/how-it-works` |

Use these phrases naturally where they describe the product. Do not add unsupported capabilities, repetitive city/county doorway pages, hidden copy, purchased links, or invented ratings. The public map covers county-class roads, and the iPhone app is a TestFlight beta; keep those limits clear.

## Establish the brand outside the site

On accounts the owner controls, make the product name and official URL consistent: **RydAR**, **https://rydar.org/**. Check the GitHub repository's website field and product description, the TestFlight description, and the eventual App Store listing. Link to the official site from relevant existing profiles. Seek useful mentions from local road-safety organizations, driving educators, and Arkansas community publications when there is a real reason to feature the project. Outreach is a separate owner action; no messages were sent or external profiles edited here.

## Measure and iterate

Once Search Console has data, record the launch date and a baseline, then review weekly. Filter branded queries separately from nonbranded queries. Track impressions, clicks, CTR, average position, indexed pages, and Google's selected canonical. Compare equivalent time windows by country and device. Average position and a single personal Google search are not a stable universal rank.

Fix indexing errors first. If the brand page is indexed correctly but still loses to other entities named Rydar, prioritize accurate external references and links that distinguish this Arkansas project. If a nonbranded page gets impressions but few clicks, refine its title and opening explanation using the actual queries. Add content only when it answers a real question better than the current pages.

Technical SEO makes the site eligible and easier to understand. First place for the brand or broad driving keywords still depends on Google's indexing, competing results, relevance, and external reputation. There is no guaranteed rank or recrawl deadline.
