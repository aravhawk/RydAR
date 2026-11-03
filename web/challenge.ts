// Stateless upload challenges. The server signs a timestamp and a random nonce with
// PASS_CHALLENGE_SECRET, so nothing about the phone that asked is stored. The app's
// App Attest key signs over the challenge, and each key is accepted only once.

import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

export const CHALLENGE_TTL_SECONDS = 600;
const PATTERN = /^v1\.(\d{10})\.([A-Za-z0-9_-]{22})\.([A-Za-z0-9_-]{43})$/;

function mac(secret: string, body: string): string {
  return createHmac("sha256", secret).update(body).digest("base64url");
}

export function issueChallenge(secret: string, nowMs = Date.now()): string {
  const body = `v1.${Math.floor(nowMs / 1000)}.${randomBytes(16).toString("base64url")}`;
  return `${body}.${mac(secret, body)}`;
}

export function checkChallenge(secret: string, value: unknown, nowMs = Date.now()): boolean {
  if (typeof value !== "string" || value.length > 128) return false;
  const match = PATTERN.exec(value);
  if (!match) return false;
  const body = value.slice(0, value.lastIndexOf("."));
  const expected = Buffer.from(mac(secret, body));
  const given = Buffer.from(match[3]);
  if (expected.length !== given.length || !timingSafeEqual(expected, given)) return false;
  const age = nowMs / 1000 - Number(match[1]);
  return age >= -30 && age <= CHALLENGE_TTL_SECONDS;
}
