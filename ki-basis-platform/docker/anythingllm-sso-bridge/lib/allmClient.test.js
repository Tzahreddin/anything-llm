"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const { createAllmClient, buildLoginPath } = require("./allmClient.js");

const BASE = "http://anythingllm:3001";
const API_KEY = "test-admin-api-key-not-for-logs";

function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  };
}

describe("buildLoginPath", () => {
  it("prefers loginPath from the ALLM response", () => {
    assert.equal(
      buildLoginPath({
        token: "should-not-win",
        loginPath: "/sso/simple?token=abc",
      }),
      "/sso/simple?token=abc"
    );
  });

  it("falls back to /sso/simple?token= when loginPath is absent", () => {
    assert.equal(
      buildLoginPath({ token: "tok-1" }),
      "/sso/simple?token=tok-1"
    );
  });
});

describe("createAllmClient", () => {
  it("lists users, finds by username, and GETs issue-auth-token with Bearer key", async () => {
    const calls = [];
    const fetchImpl = async (url, options) => {
      calls.push({ url, options });
      if (url.endsWith("/api/v1/admin/users")) {
        return jsonResponse(200, {
          users: [{ id: 7, username: "thomas" }],
        });
      }
      if (url.endsWith("/api/v1/users/7/issue-auth-token")) {
        return jsonResponse(200, {
          token: "sso-token-secret",
          loginPath: "/sso/simple?token=sso-token-secret",
        });
      }
      return jsonResponse(404, {});
    };

    const client = createAllmClient({
      baseUrl: BASE,
      apiKey: API_KEY,
      fetchImpl,
    });
    const result = await client.issueSimpleSsoLogin({
      allmUsername: "thomas",
      autoCreate: false,
    });

    assert.equal(result.status, "ok");
    assert.equal(result.loginPath, "/sso/simple?token=sso-token-secret");
    assert.equal(result.token, undefined);
    assert.equal(calls[0].options.method, "GET");
    assert.equal(calls[1].options.method, "GET");
    assert.equal(
      calls[1].options.headers.Authorization,
      `Bearer ${API_KEY}`
    );
    assert.deepEqual(
      Object.keys(result).sort(),
      ["loginPath", "status"]
    );
  });

  it("returns missing when ALLM user is absent and auto-create is off", async () => {
    const fetchImpl = async (url) => {
      if (url.endsWith("/api/v1/admin/users")) {
        return jsonResponse(200, { users: [] });
      }
      throw new Error("unexpected call");
    };
    const client = createAllmClient({
      baseUrl: BASE,
      apiKey: API_KEY,
      fetchImpl,
    });
    const result = await client.issueSimpleSsoLogin({
      allmUsername: "ghost",
      autoCreate: false,
    });
    assert.equal(result.status, "missing");
  });

  it("creates the ALLM user when auto-create is on, then issues a token", async () => {
    const calls = [];
    const fetchImpl = async (url, options) => {
      calls.push({ url, method: options.method, body: options.body });
      if (url.endsWith("/api/v1/admin/users") && options.method === "GET") {
        return jsonResponse(200, { users: [] });
      }
      if (url.endsWith("/api/v1/admin/users/new")) {
        const payload = JSON.parse(options.body);
        assert.equal(payload.username, "newbie");
        assert.equal(payload.role, "default");
        assert.equal(typeof payload.password, "string");
        assert.ok(payload.password.length >= 8);
        return jsonResponse(200, { user: { id: 42, username: "newbie" } });
      }
      if (url.endsWith("/api/v1/users/42/issue-auth-token")) {
        return jsonResponse(200, {
          loginPath: "/sso/simple?token=created-token",
        });
      }
      return jsonResponse(500, {});
    };

    const client = createAllmClient({
      baseUrl: BASE,
      apiKey: API_KEY,
      fetchImpl,
    });
    const result = await client.issueSimpleSsoLogin({
      allmUsername: "newbie",
      autoCreate: true,
    });
    assert.equal(result.status, "ok");
    assert.equal(result.loginPath, "/sso/simple?token=created-token");
    assert.equal(calls[1].method, "POST");
  });

  it("returns error (502 path) when listing users fails", async () => {
    const client = createAllmClient({
      baseUrl: BASE,
      apiKey: API_KEY,
      fetchImpl: async () => jsonResponse(500, { message: "boom" }),
    });
    const result = await client.issueSimpleSsoLogin({
      allmUsername: "thomas",
    });
    assert.equal(result.status, "error");
    assert.equal(result.loginPath, undefined);
    assert.equal(result.token, undefined);
  });

  it("returns error when issue-auth-token fails", async () => {
    const fetchImpl = async (url) => {
      if (url.endsWith("/api/v1/admin/users")) {
        return jsonResponse(200, { users: [{ id: 1, username: "thomas" }] });
      }
      return jsonResponse(502, { error: "token-fail" });
    };
    const client = createAllmClient({
      baseUrl: BASE,
      apiKey: API_KEY,
      fetchImpl,
    });
    const result = await client.issueSimpleSsoLogin({
      allmUsername: "thomas",
    });
    assert.equal(result.status, "error");
  });

  it("returns error on network failure with no anonymous fallback", async () => {
    const client = createAllmClient({
      baseUrl: BASE,
      apiKey: API_KEY,
      fetchImpl: async () => {
        throw new Error("ECONNREFUSED");
      },
    });
    const result = await client.issueSimpleSsoLogin({
      allmUsername: "thomas",
    });
    assert.equal(result.status, "error");
    assert.equal(result.reason, "network");
  });
});
