"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const { resolveBridgeIdentity } = require("./identity.js");

const sampleMap = {
  thomas: { allmUsername: "thomas-allm" },
  alice: { allmUsername: "alice-allm" },
};

describe("resolveBridgeIdentity", () => {
  it("prefers X-authentik-username over email local-part", () => {
    const result = resolveBridgeIdentity(
      {
        "x-authentik-username": "thomas",
        "x-authentik-email": "other@example.com",
      },
      sampleMap
    );
    assert.equal(result.status, "ok");
    assert.equal(result.authentikIdentity, "thomas");
    assert.equal(result.allmUsername, "thomas-allm");
  });

  it("prefers X-authentik-username over spoofable aliases and email", () => {
    const result = resolveBridgeIdentity(
      {
        "X-authentik-username": "thomas",
        preferred_username: "alice",
        "x-authentik-email": "other@example.com",
      },
      sampleMap
    );
    assert.equal(result.status, "ok");
    assert.equal(result.authentikIdentity, "thomas");
    assert.equal(result.allmUsername, "thomas-allm");
  });

  it("denies a client-supplied preferred_username without Outpost headers", () => {
    for (const alias of [
      "preferred_username",
      "preferred-username",
      "x-authentik-preferred-username",
      "email",
    ]) {
      const result = resolveBridgeIdentity({ [alias]: "thomas" }, sampleMap);
      assert.equal(result.status, "deny", `alias ${alias} must not authenticate`);
      assert.equal(result.authentikIdentity, undefined);
      assert.equal(result.allmUsername, undefined);
    }
  });

  it("denies when the Outpost username header is empty and an alias is present", () => {
    const result = resolveBridgeIdentity(
      { "x-authentik-username": "", preferred_username: "thomas" },
      sampleMap
    );
    assert.equal(result.status, "deny");
    assert.equal(result.allmUsername, undefined);
  });

  it("denies a spoofed bare email header", () => {
    const result = resolveBridgeIdentity(
      { email: "thomas@evil.tld" },
      sampleMap
    );
    assert.equal(result.status, "deny");
    assert.equal(result.allmUsername, undefined);
  });

  it("falls back to email local-part from x-authentik-email", () => {
    const result = resolveBridgeIdentity(
      { "x-authentik-email": "thomas@example.com" },
      sampleMap
    );
    assert.equal(result.status, "ok");
    assert.equal(result.authentikIdentity, "thomas");
    assert.equal(result.allmUsername, "thomas-allm");
  });

  it("accepts X-authentik-username with alternate casing", () => {
    const result = resolveBridgeIdentity(
      { "X-Authentik-Username": "thomas" },
      sampleMap
    );
    assert.equal(result.status, "ok");
    assert.equal(result.authentikIdentity, "thomas");
  });

  it("returns deny on map miss", () => {
    const result = resolveBridgeIdentity(
      { "x-authentik-username": "unknown-user" },
      sampleMap
    );
    assert.equal(result.status, "deny");
    assert.equal(result.authentikIdentity, "unknown-user");
    assert.equal(result.allmUsername, undefined);
  });

  it("returns deny when no identity headers present", () => {
    const result = resolveBridgeIdentity({}, sampleMap);
    assert.equal(result.status, "deny");
    assert.equal(result.authentikIdentity, undefined);
    assert.equal(result.allmUsername, undefined);
  });

  it("does not expose secrets from map in returned object", () => {
    const mapWithExtra = {
      thomas: {
        allmUsername: "thomas-allm",
        tokenEnv: "OPENPROJECT_API_KEY_THOMAS",
        apiKey: "super-secret",
      },
    };
    const result = resolveBridgeIdentity(
      { "x-authentik-username": "thomas" },
      mapWithExtra
    );
    assert.equal(result.status, "ok");
    assert.deepEqual(Object.keys(result).sort(), [
      "allmUsername",
      "authentikIdentity",
      "status",
    ]);
    assert.equal(result.allmUsername, "thomas-allm");
    assert.equal(result.tokenEnv, undefined);
    assert.equal(result.apiKey, undefined);
  });
});
