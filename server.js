"use strict";

const http = require("node:http");

const DEFAULT_PORT = 3000;

/**
 * Send a JSON response.
 * HEAD responses carry the same headers (including Content-Length) but no body.
 */
function sendJson(req, res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
  });
  if (req.method === "HEAD") {
    res.end();
    return;
  }
  res.end(body);
}

/**
 * Create the request handler.
 *
 * Replace the routing below with the real cline.bot behaviour. Everything that
 * survives a deployment must come from the image, so keep the module free of
 * runtime writes to disk.
 */
function createApp(options = {}) {
  const name = options.name ?? process.env.APP_NAME ?? "cline.bot";
  const version = options.version ?? "0.1.0";
  const startedAt = new Date().toISOString();

  return http.createServer((req, res) => {
    const host = req.headers.host ?? "localhost";
    let url;
    try {
      url = new URL(req.url ?? "/", `http://${host}`);
    } catch {
      sendJson(req, res, 400, { error: "bad_request" });
      return;
    }

    if (req.method !== "GET" && req.method !== "HEAD") {
      res.setHeader("allow", "GET, HEAD");
      sendJson(req, res, 405, { error: "method_not_allowed" });
      return;
    }

    if (url.pathname === "/healthz") {
      sendJson(req, res, 200, { status: "ok", uptime: process.uptime() });
      return;
    }

    if (url.pathname === "/") {
      sendJson(req, res, 200, {
        name,
        version,
        startedAt,
        endpoints: ["/", "/healthz"],
      });
      return;
    }

    sendJson(req, res, 404, { error: "not_found", path: url.pathname });
  });
}

/**
 * Start the server on 0.0.0.0 so the platform proxy can reach it.
 * The port comes from PORT, which Deplexo sets from deplexo.yaml run.port.
 */
function start(port = Number.parseInt(process.env.PORT ?? "", 10) || DEFAULT_PORT, options = {}) {
  const server = createApp(options);
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "0.0.0.0", () => resolve(server));
  });
}

module.exports = { createApp, start, DEFAULT_PORT };

if (require.main === module) {
  const port = Number.parseInt(process.env.PORT ?? "", 10) || DEFAULT_PORT;

  const server = createApp();
  server.listen(port, "0.0.0.0", () => {
    console.log(`cline.bot listening on 0.0.0.0:${port}`);
  });

  const shutdown = (signal) => {
    console.log(`received ${signal}, shutting down`);
    server.close(() => process.exit(0));
    // Do not wait forever for in-flight connections.
    setTimeout(() => process.exit(1), 10_000).unref();
  };

  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}
