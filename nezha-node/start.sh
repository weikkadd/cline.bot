#!/bin/sh
# Entrypoint for the Nezha v2 agent on Deplexo.
#
# Deplexo specifics this script works around:
#   * The container root filesystem is READ-ONLY at runtime. The agent
#     persists its config next to the binary by default, which fails there,
#     so the config path is redirected to the persistent /data volume.
#   * /tmp and /data are mounted NOEXEC. The agent binary is baked into the
#     image instead of being downloaded at runtime, so nothing has to be
#     executed from a mounted volume.
#   * Environment variables are runtime-only. Secrets come from the
#     dashboard, never from the image.
#
# NZ_ variables consumed by the agent (see nezhahq/agent model/config.go):
#   NZ_SERVER          panel gRPC address, e.g. panel.example.com:8008
#   NZ_CLIENT_SECRET   the agent's client secret from the dashboard
#   NZ_TLS             "true" when the panel serves gRPC over TLS
#   NZ_INSECURE_TLS    "true" to skip certificate verification
#   NZ_UUID            optional; generated and persisted when omitted
#   NZ_REPORT_DELAY    report interval in seconds, 1-4 (default 3)
#   NZ_DISABLE_AUTO_UPDATE / NZ_DISABLE_FORCE_UPDATE
#   NZ_DISABLE_COMMAND_EXECUTE   block the panel from running commands
#   NZ_DISABLE_NAT / NZ_DISABLE_SEND_QUERY
#   NZ_SKIP_PROCS_COUNT / NZ_SKIP_CONNECTION_COUNT
set -u

log() {
  echo "[nezha $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

fail() {
  log "FATAL: $*"
  exit 1
}

# ---- required configuration -------------------------------------------------

SERVER="${NZ_SERVER:-}"
SECRET="${NZ_CLIENT_SECRET:-}"

[ -n "$SERVER" ] || fail "NZ_SERVER is not set (expected panel gRPC address, e.g. panel.example.com:8008)"
[ -n "$SECRET" ] || fail "NZ_CLIENT_SECRET is not set"

# Log presence only, never the value.
log "server=$SERVER secret_len=${#SECRET} tls=${NZ_TLS:-false}"

# ---- writable config location ----------------------------------------------
# The agent saves its config (client secret, generated UUID) to disk. The
# image filesystem is read-only, so use the persistent data volume. /tmp is
# the last resort: it is writable but NOEXEC and is cleared on restart, so a
# config stored there loses the generated UUID and the node shows up twice in
# the panel.

CONFIG_DIR=""
for d in /data /tmp; do
  [ -n "$d" ] || continue
  if mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then
    CONFIG_DIR="$d"
    break
  fi
done
[ -n "$CONFIG_DIR" ] || fail "no writable directory for the agent config"

if [ "$CONFIG_DIR" != "/data" ]; then
  log "WARNING: /data is not writable, using $CONFIG_DIR. The agent identity may change on every redeploy."
fi

CONFIG_PATH="$CONFIG_DIR/nezha-agent-config.yml"
log "config_path=$CONFIG_PATH"

# The agent derives its default config path from the binary location
# (read-only image), so pass -c explicitly.

# ---- defaults ---------------------------------------------------------------
# Reporting every 3 seconds is the upstream default; keep it.
export NZ_REPORT_DELAY="${NZ_REPORT_DELAY:-3}"

# Debug logging is the only way to see why a connection fails: without it
# the agent stays silent when it cannot reach the panel. Cheap and useful
# in a container that has no other diagnostics.
export NZ_DEBUG="${NZ_DEBUG:-true}"

# The image is immutable and version-pinned. Self-update would try to
# replace the binary in a read-only filesystem, so turn it off unless the
# operator explicitly opts in.
export NZ_DISABLE_AUTO_UPDATE="${NZ_DISABLE_AUTO_UPDATE:-true}"
export NZ_DISABLE_FORCE_UPDATE="${NZ_DISABLE_FORCE_UPDATE:-true}"

# The panel can instruct the agent to execute shell commands. On a shared
# host that is remote code execution by another account, so it stays off
# unless the operator explicitly enables it.
export NZ_DISABLE_COMMAND_EXECUTE="${NZ_DISABLE_COMMAND_EXECUTE:-true}"

# Container metrics that are meaningless or misleading inside an isolated
# container: the NAT traversal and outbound query features are not useful
# for a hosted node, and process/connection counts reflect the container
# rather than the host.
export NZ_DISABLE_NAT="${NZ_DISABLE_NAT:-true}"
export NZ_DISABLE_SEND_QUERY="${NZ_DISABLE_SEND_QUERY:-true}"
export NZ_SKIP_PROCS_COUNT="${NZ_SKIP_PROCS_COUNT:-true}"
export NZ_SKIP_CONNECTION_COUNT="${NZ_SKIP_CONNECTION_COUNT:-true}"

# ---- connectivity preflight -------------------------------------------------
# A wrong panel address is the most common setup mistake and the agent
# reports it only in debug mode. Probe it here so the failure is obvious in
# the deployment logs. The probe uses curl against the gRPC port; a
# non-HTTP response still proves the port is open.

PROBE_HOST="${SERVER%%:*}"
PROBE_PORT="${SERVER##*:}"
# A bare "host" means the default gRPC port.
if [ "$PROBE_PORT" = "$SERVER" ]; then
  PROBE_PORT=8008
fi

PROBE_RESULT="$(curl -s -o /dev/null -w '%{http_code}' \
  --connect-timeout 8 --max-time 15 \
  "http://${PROBE_HOST}:${PROBE_PORT}/" 2>/dev/null)"

if [ -n "$PROBE_RESULT" ] && [ "$PROBE_RESULT" != "000" ]; then
  log "preflight: ${PROBE_HOST}:${PROBE_PORT} reachable (HTTP ${PROBE_RESULT})"
else
  log "preflight: ${PROBE_HOST}:${PROBE_PORT} NOT reachable. Check NZ_SERVER, and confirm the panel's gRPC port (8008 by default) is exposed to the internet."
fi

# ---- run with supervision ----------------------------------------------------
# The agent exits when the panel connection drops. Restart it so the node
# keeps reporting for the lifetime of the container.

ATTEMPT=0
while [ "$ATTEMPT" -lt 100 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  log "starting agent (attempt $ATTEMPT)"

  /usr/local/bin/nezha-agent -c "$CONFIG_PATH" &
  AGENT_PID=$!

  # Forward termination to the agent so the container stops promptly
  # instead of waiting out the full grace period.
  term() {
    log "received termination signal, stopping agent"
    kill -TERM "$AGENT_PID" 2>/dev/null
    wait "$AGENT_PID" 2>/dev/null
    exit 0
  }
  trap term TERM INT

  wait "$AGENT_PID"
  STATUS=$?
  # A signal makes wait return 128+signum; the trap normally exits first, so
  # this only matters if the trap was not yet installed.
  if [ "$STATUS" -gt 128 ]; then
    log "agent terminated by signal $((STATUS - 128))"
  else
    log "agent exited with status $STATUS"
  fi
  sleep 5
done

log "giving up after $ATTEMPT attempts"
exit 1
