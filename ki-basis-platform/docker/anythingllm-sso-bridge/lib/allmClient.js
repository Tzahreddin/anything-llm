"use strict";

const crypto = require("node:crypto");

function trimSlash(url) {
  return String(url || "").replace(/\/+$/, "");
}

function usersFromListBody(body) {
  if (Array.isArray(body)) {
    return body;
  }
  if (Array.isArray(body?.users)) {
    return body.users;
  }
  return [];
}

function userFromCreateBody(body) {
  if (body?.user && typeof body.user === "object") {
    return body.user;
  }
  if (body?.id !== undefined && body?.username) {
    return body;
  }
  return undefined;
}

function buildLoginPath(body) {
  const loginPath = body?.loginPath;
  if (typeof loginPath === "string" && loginPath.trim() !== "") {
    return loginPath.startsWith("/") ? loginPath : `/${loginPath}`;
  }
  const token = body?.token;
  if (typeof token === "string" && token.trim() !== "") {
    return `/sso/simple?token=${encodeURIComponent(token)}`;
  }
  return undefined;
}

function createAllmClient({
  baseUrl,
  apiKey,
  fetchImpl = globalThis.fetch,
} = {}) {
  const root = trimSlash(baseUrl);

  function authHeaders(extra = {}) {
    return {
      Authorization: `Bearer ${apiKey}`,
      Accept: "application/json",
      ...extra,
    };
  }

  async function requestJson(method, path, body) {
    if (!root || !apiKey) {
      return { status: "error", reason: "config" };
    }

    let response;
    try {
      response = await fetchImpl(`${root}${path}`, {
        method,
        headers: authHeaders(
          body !== undefined ? { "Content-Type": "application/json" } : {}
        ),
        body: body !== undefined ? JSON.stringify(body) : undefined,
      });
    } catch {
      return { status: "error", reason: "network" };
    }

    let parsed;
    try {
      parsed = await response.json();
    } catch {
      parsed = undefined;
    }

    if (!response.ok) {
      return { status: "error", reason: "http", httpStatus: response.status };
    }

    return { status: "ok", body: parsed };
  }

  async function findUserByUsername(username) {
    const result = await requestJson("GET", "/api/v1/admin/users");
    if (result.status !== "ok") {
      return result;
    }

    const match = usersFromListBody(result.body).find(
      (user) => user && String(user.username) === String(username)
    );
    if (!match) {
      return { status: "missing" };
    }
    return { status: "ok", user: match };
  }

  async function createUser(username) {
    const password = crypto.randomBytes(32).toString("base64url");
    const result = await requestJson("POST", "/api/v1/admin/users/new", {
      username,
      password,
      role: "default",
    });
    if (result.status !== "ok") {
      return result;
    }
    const user = userFromCreateBody(result.body);
    if (!user?.id) {
      return { status: "error", reason: "create-shape" };
    }
    return { status: "ok", user };
  }

  async function issueAuthToken(userId) {
    const result = await requestJson(
      "GET",
      `/api/v1/users/${encodeURIComponent(String(userId))}/issue-auth-token`
    );
    if (result.status !== "ok") {
      return result;
    }
    const loginPath = buildLoginPath(result.body);
    if (!loginPath) {
      return { status: "error", reason: "token-shape" };
    }
    return { status: "ok", loginPath };
  }

  async function issueSimpleSsoLogin({ allmUsername, autoCreate = false } = {}) {
    const found = await findUserByUsername(allmUsername);
    if (found.status === "error") {
      return found;
    }

    let user = found.user;
    if (found.status === "missing") {
      if (!autoCreate) {
        return { status: "missing" };
      }
      const created = await createUser(allmUsername);
      if (created.status !== "ok") {
        return created;
      }
      user = created.user;
    }

    if (user?.id === undefined || user?.id === null) {
      return { status: "error", reason: "user-id" };
    }

    return issueAuthToken(user.id);
  }

  return {
    findUserByUsername,
    createUser,
    issueAuthToken,
    issueSimpleSsoLogin,
  };
}

module.exports = {
  createAllmClient,
  buildLoginPath,
  usersFromListBody,
};
