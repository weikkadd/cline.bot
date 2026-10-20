"use strict";

const assert = require("node:assert/strict");
const { after, before, describe, it } = require("node:test");

const { createApp } = require("../server.js");

describe("cline.bot HTTP service", () => {
  let server;
  let baseUrl;

  before(async () => {
    server = createApp();
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const { port } = server.address();
    baseUrl = `http://127.0.0.1:${port}`;
  });

  after(async () => {
    await new Promise((resolve) => server.close(resolve));
  });

  it("serves service metadata on /", async () => {
    const res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type"), /application\/json/);

    const body = await res.json();
    assert.equal(body.name, "cline.bot");
    assert.deepEqual(body.endpoints, ["/", "/healthz"]);
  });

  it("reports healthy on /healthz", async () => {
    const res = await fetch(`${baseUrl}/healthz`);
    assert.equal(res.status, 200);

    const body = await res.json();
    assert.equal(body.status, "ok");
    assert.equal(typeof body.uptime, "number");
  });

  it("returns 404 for unknown paths", async () => {
    const res = await fetch(`${baseUrl}/nope`);
    assert.equal(res.status, 404);

    const body = await res.json();
    assert.equal(body.error, "not_found");
  });

  it("rejects unsupported methods", async () => {
    const res = await fetch(`${baseUrl}/`, { method: "POST" });
    assert.equal(res.status, 405);
    assert.equal(res.headers.get("allow"), "GET, HEAD");
  });

  it("answers HEAD without a body", async () => {
    const res = await fetch(`${baseUrl}/healthz`, { method: "HEAD" });
    assert.equal(res.status, 200);
    assert.equal(await res.text(), "");
  });
});
