"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const {
  autoCreateEnabled,
  createRequestHandler,
  joinPublicRedirect,
  MSG_DENY_UNMAPPED,
  MSG_DENY_NOT_PROVISIONED,
  MSG_BAD_GATEWAY,
} = require("./server.js");

const map = {
  thomas: { allmUsername: "thomas" },
};

function mockReq({ method = "GET", url = "/", headers = {} } = {}) {
  return { method, url, headers };
}

function mockRes() {
  return {
    statusCode: 0,
    headers: {},
    body: "",
    headersSent: false,
    writeHead(code, hdrs = {}) {
      this.statusCode = code;
      this.headersSent = true;
      for (const [key, value] of Object.entries(hdrs)) {
        this.headers[key.toLowerCase()] = value;
      }
    },
    end(chunk) {
      if (chunk) {
        this.body += Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
      }
    },
  };
}

function capturingLog() {
  const entries = [];
  return {
    entries,
    info(obj) {
      entries.push({ level: "info", ...obj });
    },
    error(obj) {
      entries.push({ level: "error", ...obj });
    },
  };
}

function assertNoSecrets(entries, secrets) {
  const blob = JSON.stringify(entries);
  for (const secret of secrets) {
    assert.equal(blob.includes(secret), false, `log leaked ${secret}`);
  }
}

describe("autoCreateEnabled", () => {
  it("is true only for ALLM_SSO_BRIDGE_AUTO_CREATE=1", () => {
    assert.equal(autoCreateEnabled("1"), true);
    assert.equal(autoCreateEnabled("true"), false);
    assert.equal(autoCreateEnabled("0"), false);
    assert.equal(autoCreateEnabled(undefined), false);
  });
});

describe("joinPublicRedirect", () => {
  it("joins public base and loginPath and appends redirectTo", () => {
    assert.equal(
      joinPublicRedirect(
        "http://127.0.0.1:3003",
        "/sso/simple?token=abc",
        "/workspaces/main"
      ),
      "http://127.0.0.1:3003/sso/simple?token=abc&redirectTo=%2Fworkspaces%2Fmain"
    );
  });
});

describe("SSO HTTP handler", () => {
  it("GET /health returns 200", async () => {
    const handle = createRequestHandler({ identityMap: map });
    const res = mockRes();
    await handle(mockReq({ url: "/health" }), res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body, "ok");
  });

  it("denies unmapped Authentik users with 403 German text", async () => {
    const log = capturingLog();
    const handle = createRequestHandler({ identityMap: map, log });
    const res = mockRes();
    await handle(
      mockReq({
        url: "/sso/start",
        headers: { "x-authentik-username": "unknown" },
      }),
      res
    );
    assert.equal(res.statusCode, 403);
    assert.equal(res.body, MSG_DENY_UNMAPPED);
  });

  it("denies missing identity headers with 403 German text", async () => {
    const handle = createRequestHandler({ identityMap: map });
    const res = mockRes();
    await handle(mockReq({ url: "/sso/start" }), res);
    assert.equal(res.statusCode, 403);
    assert.equal(res.body, MSG_DENY_UNMAPPED);
  });

  it("returns 403 nicht freigeschaltet when ALLM user is missing", async () => {
    const log = capturingLog();
    const handle = createRequestHandler({
      identityMap: map,
      log,
      allmClient: {
        issueSimpleSsoLogin: async () => ({ status: "missing" }),
      },
    });
    const res = mockRes();
    await handle(
      mockReq({
        url: "/sso/start",
        headers: { "x-authentik-username": "thomas" },
      }),
      res
    );
    assert.equal(res.statusCode, 403);
    assert.equal(res.body, MSG_DENY_NOT_PROVISIONED);
    assert.match(res.body, /nicht freigeschaltet/);
  });

  it("returns 502 on ALLM failure with no anonymous fallback", async () => {
    const log = capturingLog();
    const apiKey = "live-admin-key";
    const token = "minted-sso-token";
    const handle = createRequestHandler({
      identityMap: map,
      log,
      apiKey,
      allmClient: {
        issueSimpleSsoLogin: async () => ({
          status: "error",
          reason: "http",
        }),
      },
    });
    const res = mockRes();
    await handle(
      mockReq({
        url: "/",
        headers: { "x-authentik-username": "thomas" },
      }),
      res
    );
    assert.equal(res.statusCode, 502);
    assert.equal(res.body, MSG_BAD_GATEWAY);
    assert.equal(res.headers.location, undefined);
    assertNoSecrets(log.entries, [apiKey, token]);
  });

  it("redirects 302 to PUBLIC_BASE + loginPath on success", async () => {
    const log = capturingLog();
    const token = "sso-token-secret";
    const apiKey = "admin-key-secret";
    const handle = createRequestHandler({
      identityMap: map,
      log,
      publicBase: "http://127.0.0.1:3003",
      redirectTo: "/home",
      apiKey,
      allmClient: {
        issueSimpleSsoLogin: async ({ allmUsername, autoCreate }) => {
          assert.equal(allmUsername, "thomas");
          assert.equal(autoCreate, false);
          return { status: "ok", loginPath: `/sso/simple?token=${token}` };
        },
      },
    });
    const res = mockRes();
    await handle(
      mockReq({
        url: "/sso/start",
        headers: { "x-authentik-username": "thomas" },
      }),
      res
    );
    assert.equal(res.statusCode, 302);
    assert.equal(
      res.headers.location,
      "http://127.0.0.1:3003/sso/simple?token=sso-token-secret&redirectTo=%2Fhome"
    );
    assertNoSecrets(log.entries, [token, apiKey]);
    const redirectLog = log.entries.find((e) => e.msg === "sso-redirect");
    assert.equal(redirectLog.allmUsername, "thomas");
    assert.equal(redirectLog.loginPath, undefined);
    assert.equal(redirectLog.token, undefined);
  });
});
