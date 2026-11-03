import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { AttestationError, decodeCbor, sha256, verifyAssertion, verifyAttestation } from "../appattest.ts";

const sample = JSON.parse(
  readFileSync(new URL("./fixtures/appattest-ios-14.4.json", import.meta.url), "utf8"),
) as Record<string, string>;
// An assertion the same iPhone made with the same key, right after the attestation.
const assertionSample = JSON.parse(
  readFileSync(new URL("./fixtures/appattest-ios-14.4-assertion.json", import.meta.url), "utf8"),
) as Record<string, string>;

const genuine = {
  attestation: Buffer.from(sample.attestationBase64, "base64"),
  keyId: sample.keyIdBase64,
  clientDataHash: sha256(Buffer.from(sample.clientDataBase64, "base64")),
  appId: `${sample.teamIdentifier}.${sample.bundleIdentifier}`,
  allowDevelopment: true,
  now: new Date("2021-01-23T12:13:35Z"),
};

test("a real attestation from an iPhone verifies and yields its public key", () => {
  const verified = verifyAttestation(genuine);
  assert.equal(verified.environment, "development");
  assert.match(verified.publicKeyPem, /^-----BEGIN PUBLIC KEY-----/);
});

const assertionInput = () => ({
  assertion: Buffer.from(assertionSample.assertionBase64, "base64"),
  clientDataHash: sha256(Buffer.from(assertionSample.clientDataBase64, "base64")),
  publicKeyPem: verifyAttestation(genuine).publicKeyPem,
  appId: genuine.appId,
  previousCounter: 0,
});

test("a real assertion verifies against the attested key", () => {
  assert.deepEqual(verifyAssertion(assertionInput()), { counter: Number(assertionSample.counter) });
});

test("an assertion is accepted once: its counter must beat the stored one", () => {
  assert.throws(() => verifyAssertion({ ...assertionInput(), previousCounter: 1 }), AttestationError);
});

test("an assertion over different bytes, for another app, or from another key fails", () => {
  assert.throws(() => verifyAssertion({ ...assertionInput(), clientDataHash: sha256(Buffer.from("x")) }), AttestationError);
  assert.throws(() => verifyAssertion({ ...assertionInput(), appId: "XLR6H6DKHH.org.rydar.app" }), AttestationError);
  const other = "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEf+kVNGzDinuYPJPR0ENf2KvaVnAE0yxYhmVRlXq0ePfLKvi6Rff6eOrGLEnk+c3AhLUDFPECM9qbdvpEKiu4cg==\n-----END PUBLIC KEY-----\n";
  assert.throws(() => verifyAssertion({ ...assertionInput(), publicKeyPem: other }), AttestationError);
  assert.throws(() => verifyAssertion({ ...assertionInput(), assertion: Buffer.from([0xa0]) }), AttestationError);
});

const tampered: Array<[string, Partial<typeof genuine>]> = [
  ["a development key when only production is allowed", { allowDevelopment: false }],
  ["another app", { appId: "XLR6H6DKHH.org.rydar.app" }],
  ["an expired certificate", { now: new Date("2026-11-02T00:00:00Z") }],
  ["a changed payload", { clientDataHash: sha256(Buffer.from("other bytes")) }],
  ["another key id", { keyId: sha256(Buffer.from("k")).toString("base64") }],
];

for (const [name, change] of tampered) {
  test(`rejects ${name}`, () => {
    assert.throws(() => verifyAttestation({ ...genuine, ...change }), AttestationError);
  });
}

test("rejects a flipped byte anywhere in the authenticator data", () => {
  const bytes = Buffer.from(genuine.attestation);
  const at = bytes.indexOf(Buffer.from("authData")) + 12;
  bytes[at] ^= 0x01;
  assert.throws(() => verifyAttestation({ ...genuine, attestation: bytes }), AttestationError);
});

test("rejects garbage and truncated CBOR without crashing", () => {
  for (const bytes of [Buffer.alloc(0), Buffer.from([0xbf]), Buffer.from([0x5b, 0xff, 0xff]), genuine.attestation.subarray(0, 100)]) {
    assert.throws(() => verifyAttestation({ ...genuine, attestation: bytes }), AttestationError);
  }
});

test("decodes nested CBOR maps", () => {
  const value = decodeCbor(Buffer.from([0xa1, 0x61, 0x61, 0x82, 0x01, 0x42, 0xaa, 0xbb])) as Map<unknown, unknown>;
  assert.deepEqual(value.get("a"), [1, Buffer.from([0xaa, 0xbb])]);
});
