import assert from "node:assert/strict";
import { test } from "node:test";
import { CHALLENGE_TTL_SECONDS, checkChallenge, issueChallenge } from "../challenge.ts";

const secret = "s".repeat(32);

test("a fresh challenge checks out", () => {
  const challenge = issueChallenge(secret);
  assert.match(challenge, /^v1\.\d{10}\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}$/);
  assert.equal(checkChallenge(secret, challenge), true);
});

test("a challenge expires", () => {
  const issued = Date.UTC(2026, 10, 2, 12, 0, 0);
  const challenge = issueChallenge(secret, issued);
  assert.equal(checkChallenge(secret, challenge, issued + (CHALLENGE_TTL_SECONDS - 1) * 1000), true);
  assert.equal(checkChallenge(secret, challenge, issued + (CHALLENGE_TTL_SECONDS + 1) * 1000), false);
});

test("a forged or altered challenge fails", () => {
  const challenge = issueChallenge(secret);
  assert.equal(checkChallenge("t".repeat(32), challenge), false);
  const [version, time, nonce, mac] = challenge.split(".");
  assert.equal(checkChallenge(secret, [version, Number(time) + 1, nonce, mac].join(".")), false);
  assert.equal(checkChallenge(secret, 42), false);
  assert.equal(checkChallenge(secret, "x".repeat(500)), false);
});
