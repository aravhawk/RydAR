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

function countyPrefix(county: string): string | null {
  switch (county.toLowerCase()) {
    case "benton":
      return "007-";
    case "washington":
      return "143-";
    default:
      return null;
  }
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

// Benton curve ids start with 007-, Washington with 143-.
const CURVE_ID = /^(007|143)-\d{1,7}-\d{1,7}$/;

function isPass(value: unknown): value is PassBody {
  if (typeof value !== "object" || value === null) return false;
  const row = value as Record<string, unknown>;
  const latAccel = row.lat_accel_band;
  return (
    typeof row.curve_id === "string" &&
    CURVE_ID.test(row.curve_id) &&
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
