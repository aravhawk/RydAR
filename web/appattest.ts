// Verifies Apple App Attest attestation objects (once per key) and assertions (once per request).
//
// Follows Apple's "Validating apps that connect to your server", attestation steps 1-9 and
// assertion steps 1-6:
// https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server
//
// Self-contained on purpose (node:crypto only): no third-party parsing code sits between
// the network and the trust decision.

import { createHash, createPublicKey, verify as verifySignature, X509Certificate } from "node:crypto";

/** Apple App Attestation Root CA, from https://www.apple.com/certificateauthority/
 *  SHA-256 fingerprint 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32 */
export const APPLE_APP_ATTESTATION_ROOT_CA = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

const ROOT = new X509Certificate(APPLE_APP_ATTESTATION_ROOT_CA);
const NONCE_EXTENSION_OID = "1.2.840.113635.100.8.2";
const AAGUID_PRODUCTION = Buffer.concat([Buffer.from("appattest"), Buffer.alloc(7)]);
const AAGUID_DEVELOPMENT = Buffer.from("appattestdevelop");

export class AttestationError extends Error {}

export interface AttestationInput {
  /** The CBOR attestation object from DCAppAttestService.attestKey. */
  attestation: Buffer;
  /** The key identifier from DCAppAttestService.generateKey: base64 of SHA-256(public key). */
  keyId: string;
  /** The exact clientDataHash the app passed to attestKey. */
  clientDataHash: Buffer;
  /** "TEAMID.bundle.identifier". */
  appId: string;
  allowDevelopment: boolean;
  /** Time used for certificate validity. Tests pass the capture time of a recorded sample. */
  now?: Date;
}

export interface VerifiedAttestation {
  environment: "production" | "development";
  /** The attested key, as SPKI PEM. Stored by the server to check later assertions. */
  publicKeyPem: string;
}

export function verifyAttestation(input: AttestationInput): VerifiedAttestation {
  const now = input.now ?? new Date();
  const object = decodeCbor(input.attestation);
  if (!isMap(object)) throw new AttestationError("attestation is not a map");
  if (object.get("fmt") !== "apple-appattest") throw new AttestationError("unexpected format");
  const statement = object.get("attStmt");
  const authData = object.get("authData");
  if (!isMap(statement) || !Buffer.isBuffer(authData)) throw new AttestationError("missing fields");
  const x5c = statement.get("x5c");
  if (!Array.isArray(x5c) || x5c.length < 2 || !x5c.every((item) => Buffer.isBuffer(item))) {
    throw new AttestationError("missing certificate chain");
  }

  // 1. The credential certificate chains to Apple's App Attestation root, and every link is in date.
  const credential = new X509Certificate(x5c[0] as Buffer);
  const intermediate = new X509Certificate(x5c[1] as Buffer);
  checkIssued(intermediate, ROOT, now);
  checkIssued(credential, intermediate, now);

  // 2-4. nonce = SHA-256(authData || clientDataHash) must equal the certificate's nonce extension.
  if (input.clientDataHash.length !== 32) throw new AttestationError("bad client data hash");
  const nonce = sha256(Buffer.concat([authData, input.clientDataHash]));
  const embedded = credentialNonce(credential.raw);
  if (!embedded || !embedded.equals(nonce)) throw new AttestationError("nonce mismatch");

  // 5. The key identifier is the SHA-256 of the credential's public key.
  const keyId = Buffer.from(input.keyId, "base64");
  if (keyId.length !== 32) throw new AttestationError("bad key id");
  const jwk = credential.publicKey.export({ format: "jwk" }) as { crv?: string; x?: string; y?: string };
  if (jwk.crv !== "P-256" || !jwk.x || !jwk.y) throw new AttestationError("unexpected key type");
  const point = Buffer.concat([
    Buffer.from([0x04]),
    Buffer.from(jwk.x, "base64url"),
    Buffer.from(jwk.y, "base64url"),
  ]);
  if (!sha256(point).equals(keyId)) throw new AttestationError("key id mismatch");

  // 6-9. Authenticator data: our App ID, a fresh counter, the environment, and the same key.
  if (authData.length < 55) throw new AttestationError("short authenticator data");
  if (!authData.subarray(0, 32).equals(sha256(Buffer.from(input.appId)))) {
    throw new AttestationError("app id mismatch");
  }
  if (authData.readUInt32BE(33) !== 0) throw new AttestationError("counter is not zero");
  const aaguid = authData.subarray(37, 53);
  let environment: VerifiedAttestation["environment"];
  if (aaguid.equals(AAGUID_PRODUCTION)) {
    environment = "production";
  } else if (aaguid.equals(AAGUID_DEVELOPMENT) && input.allowDevelopment) {
    environment = "development";
  } else {
    throw new AttestationError("environment not accepted");
  }
  const credentialIdLength = authData.readUInt16BE(53);
  const credentialId = authData.subarray(55, 55 + credentialIdLength);
  if (credentialId.length !== credentialIdLength || !credentialId.equals(keyId)) {
    throw new AttestationError("credential id mismatch");
  }
  return {
    environment,
    publicKeyPem: credential.publicKey.export({ type: "spki", format: "pem" }).toString(),
  };
}

export interface AssertionInput {
  /** The CBOR assertion from DCAppAttestService.generateAssertion. */
  assertion: Buffer;
  /** The exact clientDataHash the app passed to generateAssertion. */
  clientDataHash: Buffer;
  /** The key's public key, saved when its attestation was accepted. */
  publicKeyPem: string;
  /** "TEAMID.bundle.identifier". */
  appId: string;
  /** The highest counter already accepted for this key. */
  previousCounter: number;
}

/** Returns the assertion's counter. The caller must store it so the same assertion cannot be replayed. */
export function verifyAssertion(input: AssertionInput): { counter: number } {
  const object = decodeCbor(input.assertion);
  if (!isMap(object)) throw new AttestationError("assertion is not a map");
  const signature = object.get("signature");
  const authData = object.get("authenticatorData");
  if (!Buffer.isBuffer(signature) || !Buffer.isBuffer(authData) || authData.length < 37) {
    throw new AttestationError("missing fields");
  }
  if (input.clientDataHash.length !== 32) throw new AttestationError("bad client data hash");
  // 1-3. The key signed nonce = SHA-256(authenticatorData || clientDataHash) (ECDSA P-256, SHA-256).
  const nonce = sha256(Buffer.concat([authData, input.clientDataHash]));
  let key;
  try {
    key = createPublicKey(input.publicKeyPem);
  } catch {
    throw new AttestationError("stored key unreadable");
  }
  if (!verifySignature("sha256", nonce, key, signature)) throw new AttestationError("signature does not verify");
  // 4. Our App ID.
  if (!authData.subarray(0, 32).equals(sha256(Buffer.from(input.appId)))) {
    throw new AttestationError("app id mismatch");
  }
  // 5. The counter only ever goes up.
  const counter = authData.readUInt32BE(33);
  if (counter <= input.previousCounter) throw new AttestationError("counter did not increase");
  return { counter };
}

function checkIssued(child: X509Certificate, issuer: X509Certificate, now: Date): void {
  if (!child.checkIssued(issuer) || !child.verify(issuer.publicKey)) {
    throw new AttestationError("certificate chain does not verify");
  }
  for (const certificate of [child, issuer]) {
    const from = new Date(certificate.validFrom).getTime();
    const to = new Date(certificate.validTo).getTime();
    if (!(from <= now.getTime() && now.getTime() <= to)) throw new AttestationError("certificate out of date");
  }
}

export function sha256(data: Buffer): Buffer {
  return createHash("sha256").update(data).digest();
}

// ---------------------------------------------------------------------------
// Minimal DER reader: just enough to find one extension in an X.509 certificate.

interface Tlv {
  tag: number;
  start: number; // first content byte
  end: number; // one past the last content byte
}

function readTlv(buffer: Buffer, offset: number, limit = buffer.length): Tlv {
  if (offset + 2 > limit) throw new AttestationError("truncated DER");
  const tag = buffer[offset];
  let length = buffer[offset + 1];
  let start = offset + 2;
  if (length & 0x80) {
    const bytes = length & 0x7f;
    if (bytes < 1 || bytes > 4 || start + bytes > limit) throw new AttestationError("bad DER length");
    length = 0;
    for (let i = 0; i < bytes; i++) length = length * 256 + buffer[start + i];
    start += bytes;
  }
  const end = start + length;
  if (end > limit) throw new AttestationError("truncated DER");
  return { tag, start, end };
}

function children(buffer: Buffer, parent: Tlv): Tlv[] {
  const items: Tlv[] = [];
  let offset = parent.start;
  while (offset < parent.end) {
    const item = readTlv(buffer, offset, parent.end);
    items.push(item);
    offset = item.end;
  }
  return items;
}

function encodeOid(oid: string): Buffer {
  const parts = oid.split(".").map(Number);
  const bytes = [parts[0] * 40 + parts[1]];
  for (const part of parts.slice(2)) {
    const chunk = [part & 0x7f];
    let rest = Math.floor(part / 128);
    while (rest > 0) {
      chunk.unshift((rest & 0x7f) | 0x80);
      rest = Math.floor(rest / 128);
    }
    bytes.push(...chunk);
  }
  return Buffer.from(bytes);
}

/** The 32-byte nonce in extension 1.2.840.113635.100.8.2: SEQUENCE { [1] { OCTET STRING } }. */
export function credentialNonce(certificate: Buffer): Buffer | null {
  const wanted = encodeOid(NONCE_EXTENSION_OID);
  const cert = readTlv(certificate, 0);
  const tbs = children(certificate, cert)[0];
  if (!tbs) return null;
  const extensionsWrapper = children(certificate, tbs).find((item) => item.tag === 0xa3);
  if (!extensionsWrapper) return null;
  const list = children(certificate, extensionsWrapper)[0];
  if (!list) return null;
  for (const extension of children(certificate, list)) {
    const parts = children(certificate, extension);
    const oid = parts[0];
    if (!oid || oid.tag !== 0x06 || !certificate.subarray(oid.start, oid.end).equals(wanted)) continue;
    const value = parts[parts.length - 1];
    if (value.tag !== 0x04) return null;
    const sequence = readTlv(certificate, value.start, value.end);
    if (sequence.tag !== 0x30) return null;
    const tagged = children(certificate, sequence).find((item) => item.tag === 0xa1);
    if (!tagged) return null;
    const octets = readTlv(certificate, tagged.start, tagged.end);
    if (octets.tag !== 0x04) return null;
    return Buffer.from(certificate.subarray(octets.start, octets.end));
  }
  return null;
}

// ---------------------------------------------------------------------------
// Minimal CBOR decoder for the attestation object: maps, arrays, byte and text strings,
// integers, and simple values. Definite lengths only, bounded depth and size.

type CborValue = number | bigint | string | boolean | null | undefined | Buffer | CborValue[] | Map<CborValue, CborValue>;

function isMap(value: CborValue): value is Map<CborValue, CborValue> {
  return value instanceof Map;
}

export function decodeCbor(data: Buffer): CborValue {
  let offset = 0;

  function length(info: number): number {
    if (info < 24) return info;
    const size = info === 24 ? 1 : info === 25 ? 2 : info === 26 ? 4 : info === 27 ? 8 : 0;
    if (size === 0) throw new AttestationError("unsupported CBOR length");
    if (offset + size > data.length) throw new AttestationError("truncated CBOR");
    let value = 0;
    for (let i = 0; i < size; i++) value = value * 256 + data[offset + i];
    offset += size;
    if (!Number.isSafeInteger(value)) throw new AttestationError("CBOR length too large");
    return value;
  }

  function take(count: number): Buffer {
    if (count > data.length - offset) throw new AttestationError("truncated CBOR");
    const slice = data.subarray(offset, offset + count);
    offset += count;
    return Buffer.from(slice);
  }

  function item(depth: number): CborValue {
    if (depth > 16) throw new AttestationError("CBOR nested too deeply");
    if (offset >= data.length) throw new AttestationError("truncated CBOR");
    const initial = data[offset++];
    const major = initial >> 5;
    const info = initial & 0x1f;
    switch (major) {
      case 0:
        return length(info);
      case 1:
        return -1 - length(info);
      case 2:
        return take(length(info));
      case 3:
        return take(length(info)).toString("utf8");
      case 4: {
        const count = length(info);
        if (count > data.length) throw new AttestationError("CBOR array too long");
        const items: CborValue[] = [];
        for (let i = 0; i < count; i++) items.push(item(depth + 1));
        return items;
      }
      case 5: {
        const count = length(info);
        if (count > data.length) throw new AttestationError("CBOR map too long");
        const map = new Map<CborValue, CborValue>();
        for (let i = 0; i < count; i++) {
          const key = item(depth + 1);
          map.set(key, item(depth + 1));
        }
        return map;
      }
      case 6:
        length(info);
        return item(depth + 1);
      default:
        if (info === 20) return false;
        if (info === 21) return true;
        if (info === 22) return null;
        if (info === 23) return undefined;
        throw new AttestationError("unsupported CBOR value");
    }
  }

  const value = item(0);
  if (offset !== data.length) throw new AttestationError("trailing CBOR bytes");
  return value;
}
