# Nezha monitoring agent (v2) as a Deplexo worker.
#
# The agent binary is baked into the image at build time on purpose:
# Deplexo mounts /tmp and /data as NOEXEC, so a binary downloaded at
# runtime cannot be executed. Baking it in also removes the runtime
# download from the startup path entirely.
#
# Build-time only. No secrets are passed as ARG or ENV here; the panel
# address and client secret are supplied as runtime environment variables.

FROM alpine:3.20 AS fetch

# unzip to extract the release archive, ca-certificates for TLS to the panel.
RUN apk add --no-cache curl unzip ca-certificates

# Pin the version so rebuilds are reproducible. Bump deliberately.
ARG NEZHA_AGENT_VERSION=v2.3.5

# BuildKit sets TARGETARCH automatically, but it must still be declared as an
# ARG to be visible inside the RUN below.
ARG TARGETARCH

# TARGETARCH is set by BuildKit. Fall back to uname for non-BuildKit builders.
RUN set -eux; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
      arch="$(uname -m)"; \
      case "$arch" in \
        x86_64|amd64) arch=amd64 ;; \
        aarch64|arm64) arch=arm64 ;; \
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
      esac; \
    fi; \
    url="https://github.com/nezhahq/agent/releases/download/${NEZHA_AGENT_VERSION}/nezha-agent_linux_${arch}.zip"; \
    echo "fetching $url"; \
    curl -fsSL --retry 3 --max-time 180 "$url" -o /tmp/agent.zip; \
    mkdir -p /tmp/agent; \
    unzip -o -q /tmp/agent.zip -d /tmp/agent; \
    bin="$(find /tmp/agent -type f -name 'nezha-agent*' | head -1)"; \
    [ -n "$bin" ] || { echo "no agent binary in archive" >&2; exit 1; }; \
    cp "$bin" /tmp/nezha-agent; \
    chmod 755 /tmp/nezha-agent


FROM alpine:3.20

# ca-certificates for TLS to the panel over the public internet.
# curl is used by the entrypoint for a connectivity preflight, since busybox
# nc has limited flag support and /dev/tcp is unavailable in busybox ash.
RUN apk add --no-cache ca-certificates curl tzdata

COPY --from=fetch /tmp/nezha-agent /usr/local/bin/nezha-agent

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Unprivileged user: Deplexo runs containers with restricted privileges.
RUN addgroup -g 1000 -S nezha && adduser -u 1000 -S -G nezha -h /home/nezha nezha

USER nezha
WORKDIR /home/nezha

# The agent persists its config (including the client secret) next to the
# binary by default. The image filesystem is read-only at runtime, so the
# config path is redirected to the persistent /data volume by start.sh.
#
# Worker app: no port, no public URL. The agent dials out to the panel.
CMD ["/usr/local/bin/start.sh"]
