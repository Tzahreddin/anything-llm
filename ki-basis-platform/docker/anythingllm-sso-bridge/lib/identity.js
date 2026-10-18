"use strict";

function normalizeHeaderName(name) {
  return String(name).toLowerCase();
}

function getHeader(headers, ...names) {
  if (!headers || typeof headers !== "object") {
    return undefined;
  }

  const lookup = new Map();
  for (const [key, value] of Object.entries(headers)) {
    lookup.set(normalizeHeaderName(key), value);
  }

  for (const name of names) {
    const value = lookup.get(normalizeHeaderName(name));
    if (value !== undefined && value !== null && String(value).trim() !== "") {
      return String(value).trim();
    }
  }

  return undefined;
}

function emailLocalPart(email) {
  const at = String(email).indexOf("@");
  if (at <= 0) {
    return undefined;
  }
  return String(email).slice(0, at).trim() || undefined;
}

// Only Outpost-controlled headers are trusted. nginx overrides exactly the
// X-authentik-* set via auth_request_set; anything else (preferred_username,
// email, …) arrives verbatim from the client and would allow impersonation of
// any mapped user whenever the canonical username header is missing.
function resolveAuthentikIdentity(headers) {
  const username = getHeader(headers, "x-authentik-username");
  if (username) {
    return username;
  }

  const email = getHeader(headers, "x-authentik-email");
  if (email) {
    return emailLocalPart(email);
  }

  return undefined;
}

function resolveBridgeIdentity(headers, map) {
  const authentikIdentity = resolveAuthentikIdentity(headers);
  if (!authentikIdentity) {
    return { status: "deny" };
  }

  const entry = map?.[authentikIdentity];
  const allmUsername = entry?.allmUsername;
  if (!allmUsername) {
    return { status: "deny", authentikIdentity };
  }

  return {
    status: "ok",
    authentikIdentity,
    allmUsername,
  };
}

module.exports = {
  resolveBridgeIdentity,
  resolveAuthentikIdentity,
  emailLocalPart,
};
