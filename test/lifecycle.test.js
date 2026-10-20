"use strict";

const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const path = require("node:path");
const { describe, it } = require("node:test");

const ENTRY = path.join(__dirname, "..", "server.js");
const PORT = 3199;
const BASE_URL = `http://127.0.0.1:${PORT}`;

describe("process lifecycle", () => {
  it("serves traffic and exits cleanly on SIGTERM", async () => {
    const child = spawn(process.execPath, [ENTRY], {
      env: { ...process.env, PORT: String(PORT) },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    try {
      // Wait for the listen banner before hitting the service.
      const deadline = Date.now() + 10_000;
      while (!stdout.includes("listening") && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      assert.match(stdout, /listening on 0\.0\.0\.0:3199/);

      const res = await fetch(`${BASE_URL}/healthz`);
      assert.equal(res.status, 200);
      assert.equal((await res.json()).status, "ok");

      const exitCode = await new Promise((resolve, reject) => {
        const timer = setTimeout(
          () => reject(new Error("server did not exit within 10s")),
          10_000,
        );
        child.once("exit", (code, signal) => {
          clearTimeout(timer);
          resolve(signal ?? code);
        });
        child.once("error", (err) => {
          clearTimeout(timer);
          reject(err);
        });
        child.kill("SIGTERM");
      });

      assert.equal(exitCode, 0, "server should exit with code 0 on SIGTERM");
    } finally {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGKILL");
      }
    }
  });
});
