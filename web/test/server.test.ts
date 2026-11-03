import assert from "node:assert/strict";
import { before, test } from "node:test";

process.env.PASS_CHALLENGE_SECRET = "s".repeat(32);
// neon() only parses the URL. Every request in this file is refused before any query runs.
process.env.DATABASE_URL = "postgres://user:pass@db.invalid/rydar";

const { default: app, MAX_BODY_BYTES, MAX_PASSES_PER_BATCH, parsePayload, registrationHash } = await import("../server.ts");

const pass = { curve_id: "007-2-3", direction: "N", speed_band_mph: 31.5, hour_bucket: 9, app_version: "1.0.0" };

let challenge = "";
before(async () => {
  const response = await app.request("/api/challenge");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  challenge = ((await response.json()) as { challenge: string }).challenge;
});

function post(body: unknown, headers: Record<string, string> = {}, path = "/api/pass") {
  return app.request(path, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function signed(overrides: Record<string, unknown> = {}) {
  return {
    key_id: Buffer.alloc(32, 7).toString("base64"),
    assertion: Buffer.from("not an assertion").toString("base64"),
    challenge,
    payload: Buffer.from(JSON.stringify({ passes: [pass] })).toString("base64"),
    ...overrides,
  };
}

test("an unsigned pass in the old format is refused", async () => {
  assert.equal((await post(pass)).status, 400);
});

test("a forged registration is refused before anything is stored", async () => {
  const registration = { key_id: Buffer.alloc(32, 7).toString("base64"), attestation: Buffer.from("fake").toString("base64"), challenge };
  assert.equal((await post(registration, {}, "/api/attest")).status, 401);
  assert.equal((await post({ ...registration, challenge: "stale" }, {}, "/api/attest")).status, 401);
  assert.equal((await post({ key_id: "short" }, {}, "/api/attest")).status, 400);
  assert.equal((await post("x".repeat(MAX_BODY_BYTES + 1), {}, "/api/attest")).status, 413);
});

test("the registration hash matches the app's construction", async () => {
  const { createHash } = await import("node:crypto");
  assert.deepEqual(registrationHash("abc"), createHash("sha256").update("rydar-attest-v1\nabc").digest());
});

test("an unknown challenge is refused", async () => {
  assert.equal((await post(signed({ challenge: "v1.1700000000.aaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }))).status, 401);
});

test("bad passes are refused before any signature work", async () => {
  const bad = { ...pass, curve_id: "002-1-1" };
  const payload = Buffer.from(JSON.stringify({ passes: [bad] })).toString("base64");
  assert.equal((await post(signed({ payload }))).status, 400);
  assert.equal((await post("{not json")).status, 400);
  assert.equal((await post(signed({ key_id: "short" }))).status, 400);
});

test("an oversized body is refused", async () => {
  const response = await post("x".repeat(MAX_BODY_BYTES + 1));
  assert.equal(response.status, 413);
});

test("a batch holds between one and the cap of passes", () => {
  assert.equal(parsePayload(Buffer.from(JSON.stringify({ passes: [] }))), null);
  assert.equal(parsePayload(Buffer.from(JSON.stringify({ passes: [pass] })))?.length, 1);
  const many = Array.from({ length: MAX_PASSES_PER_BATCH + 1 }, () => pass);
  assert.equal(parsePayload(Buffer.from(JSON.stringify({ passes: many }))), null);
  assert.equal(parsePayload(Buffer.from(JSON.stringify({ passes: [{ ...pass, hour_bucket: 24 }] }))), null);
});

test("the client data hash matches the app's construction", async () => {
  const { clientDataHash } = await import("../server.ts");
  const { createHash } = await import("node:crypto");
  const payload = Buffer.from('{"passes":[]}');
  const expected = createHash("sha256").update(`rydar-pass-v1\nabc\n`).update(payload).digest();
  assert.deepEqual(clientDataHash("abc", payload), expected);
});
