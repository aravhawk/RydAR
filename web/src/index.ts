interface PassBody {
  curve_id: string;
  direction: string;
  speed_band_mph: number;
  hour_bucket: number;
  app_version: string;
  lat_accel_band?: number | null;
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/api/pass") {
      return storePass(request, env);
    }
    if (request.method === "GET" && url.pathname.startsWith("/api/curves/")) {
      const county = decodeURIComponent(url.pathname.slice("/api/curves/".length)).replace(/\.geojson$/, "");
      if (countyPrefix(county) === null) {
        return Response.json({ error: "unknown county" }, { status: 404 });
      }
      return countyGeometry(request, env, county.toLowerCase());
    }
    if (request.method === "GET" && url.pathname.startsWith("/api/export/")) {
      const county = decodeURIComponent(url.pathname.slice("/api/export/".length)).replace(/\.csv$/, "");
      const prefix = countyPrefix(county);
      if (prefix === null) {
        return Response.json({ error: "unknown county" }, { status: 404 });
      }
      return exportCounty(env, prefix);
    }
    if (request.method === "GET" && url.pathname === "/api/health") {
      return Response.json({ ok: true });
    }
    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<Env>;

async function countyGeometry(request: Request, env: Env, county: string): Promise<Response> {
  const asset = await env.ASSETS.fetch(new URL(`/data/curves-${county}.geojson`, request.url));
  if (!asset.ok) {
    return Response.json({ error: "curve file missing" }, { status: 404 });
  }
  return new Response(asset.body, {
    headers: {
      "content-type": "application/geo+json; charset=utf-8",
      "cache-control": "public, max-age=3600",
    },
  });
}

async function storePass(request: Request, env: Env): Promise<Response> {
  let body: PassBody;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "invalid json" }, { status: 400 });
  }
  if (!isPass(body)) {
    return Response.json({ error: "missing fields" }, { status: 400 });
  }
  await env.DB.prepare(
    `INSERT INTO passes (curve_id, direction, speed_band_mph, hour_bucket, app_version, lat_accel_band)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      body.curve_id,
      body.direction,
      body.speed_band_mph,
      body.hour_bucket,
      body.app_version,
      body.lat_accel_band ?? null,
    )
    .run();
  return Response.json({ stored: true });
}

const COUNTY_FIPS: Record<string, string> = {
  arkansas: "001", ashley: "003", baxter: "005", benton: "007", boone: "009",
  bradley: "011", calhoun: "013", carroll: "015", chicot: "017", clark: "019",
  clay: "021", cleburne: "023", cleveland: "025", columbia: "027", conway: "029",
  craighead: "031", crawford: "033", crittenden: "035", cross: "037", dallas: "039",
  desha: "041", drew: "043", faulkner: "045", franklin: "047", fulton: "049",
  garland: "051", grant: "053", greene: "055", hempstead: "057", "hot spring": "059",
  howard: "061", independence: "063", izard: "065", jackson: "067", jefferson: "069",
  johnson: "071", lafayette: "073", lawrence: "075", lee: "077", lincoln: "079",
  "little river": "081", logan: "083", lonoke: "085", madison: "087", marion: "089",
  miller: "091", mississippi: "093", monroe: "095", montgomery: "097", nevada: "099",
  newton: "101", ouachita: "103", perry: "105", phillips: "107", pike: "109",
  poinsett: "111", polk: "113", pope: "115", prairie: "117", pulaski: "119",
  randolph: "121", "st. francis": "123", saline: "125", scott: "127", searcy: "129",
  sebastian: "131", sevier: "133", sharp: "135", stone: "137", union: "139",
  "van buren": "141", washington: "143", white: "145", woodruff: "147", yell: "149",
};

function countyPrefix(county: string): string | null {
  const fips = COUNTY_FIPS[county.toLowerCase().replace(/-/g, " ")];
  return fips ? `${fips}-` : null;
}

async function exportCounty(env: Env, prefix: string): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT curve_id,
            COUNT(*) AS n,
            COUNT(DISTINCT hour_bucket) AS hours
     FROM passes
     WHERE curve_id LIKE ?
     GROUP BY curve_id
     HAVING n >= 20 AND hours >= 2
     ORDER BY curve_id`,
  )
    .bind(`${prefix}%`)
    .all<{ curve_id: string; n: number; hours: number }>();
  const lines = ["curve_id,n,hour_buckets"];
  for (const row of rows.results) {
    lines.push(`${row.curve_id},${row.n},${row.hours}`);
  }
  return new Response(lines.join("\n") + "\n", {
    headers: { "content-type": "text/csv; charset=utf-8" },
  });
}

// Arkansas county FIPS are the odd numbers from 001 through 149.
const CURVE_ID = /^(\d{3})-\d{1,7}-\d{1,7}$/;

function isArkansasCurveID(id: string): boolean {
  const county = Number(id.slice(0, 3));
  return county >= 1 && county <= 149 && county % 2 === 1;
}

function isPass(value: unknown): value is PassBody {
  if (typeof value !== "object" || value === null) return false;
  const row = value as Record<string, unknown>;
  const latAccel = row.lat_accel_band;
  return (
    typeof row.curve_id === "string" &&
    CURVE_ID.test(row.curve_id) &&
    isArkansasCurveID(row.curve_id) &&
    typeof row.direction === "string" &&
    row.direction.length >= 1 &&
    row.direction.length <= 8 &&
    Number.isInteger(row.speed_band_mph) &&
    (row.speed_band_mph as number) >= 0 &&
    (row.speed_band_mph as number) <= 150 &&
    (row.speed_band_mph as number) % 5 === 0 &&
    Number.isInteger(row.hour_bucket) &&
    (row.hour_bucket as number) >= 0 &&
    (row.hour_bucket as number) <= 23 &&
    typeof row.app_version === "string" &&
    row.app_version.length >= 1 &&
    row.app_version.length <= 32 &&
    (latAccel === undefined || latAccel === null || Number.isInteger(latAccel))
  );
}
