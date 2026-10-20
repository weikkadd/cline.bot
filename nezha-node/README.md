# Nezha monitoring agent for Deplexo

Runs the [Nezha](https://github.com/nezhahq/nezha) v2 monitoring agent as a
Deplexo **worker** app. The agent dials out to your panel over gRPC and keeps
reporting system metrics; it exposes no inbound port.

```
nezha-node/
├── deplexo.yaml   # worker app, no port
├── Dockerfile     # agent v2.3.5 baked into the image
├── start.sh       # entrypoint: config location, defaults, preflight, supervision
└── .env.example   # the variables to set in the Deplexo dashboard
```

## Why the agent is baked into the image

Deplexo mounts `/tmp` and `/data` as **NOEXEC**. A binary downloaded at
runtime cannot be executed there, so the agent is downloaded during the build
and copied into the image. This also removes the download from the startup
path and makes the image reproducible.

## Why the config path is redirected

The agent persists its config next to its own binary by default
(`<binary dir>/config.yml`). On Deplexo the image filesystem is **read-only**
at runtime, so the agent would fail to write its config there. Verified
behaviour: with a read-only directory the agent hangs with no error message
and no config file.

`start.sh` therefore passes `-c /data/nezha-agent-config.yml`. `/data` is the
persistent volume, so the generated UUID and client secret survive container
replacements and the node keeps a single identity in the panel.

## Configure the node

Set these as environment variables in the Deplexo dashboard
(**Settings → Environment**). Never commit the secret.

| Variable | Required | Description |
| --- | --- | --- |
| `NZ_SERVER` | yes | Panel gRPC address, `host:port` — the port defaults to `8008` if omitted |
| `NZ_CLIENT_SECRET` | yes | The agent's client secret, copied from the panel when you add the node |
| `NZ_TLS` | no | `true` when the panel serves gRPC over TLS |
| `NZ_INSECURE_TLS` | no | `true` to skip certificate verification (self-signed panels) |

Example values:

```
NZ_SERVER=panel.example.com:8008
NZ_CLIENT_SECRET=<paste-from-panel>
NZ_TLS=true
```

### Expose the panel's gRPC port

The agent connects to the panel, so the panel must be reachable from the
internet on its gRPC port (`8008` by default). The panel's web dashboard port
is a different thing; the agent does not use it.

If the panel is behind a reverse proxy, forward the gRPC port directly. A
plain HTTP proxy that does not understand gRPC will not work.

## Deploy

The `deplexo.yaml` in this directory is a worker app, so it must be deployed
as its own repository — a Deplexo app has exactly one `deplexo.yaml` at the
source root, and `cline.bot` already occupies that slot in this repository.

To deploy:

1. Put this directory's contents at the root of a new repository.
2. Connect the repository in the Deplexo dashboard.
3. Set `NZ_SERVER` and `NZ_CLIENT_SECRET` in the app's environment settings.
4. Deploy, then check the logs.

From the terminal:

```sh
deplexo auth login
deplexo apps create --name nezha-node --repo https://github.com/you/nezha-node
deplexo link --app <APP_UUID>
deplexo deploy
deplexo deployments logs <DEPLOYMENT_UUID>
```

## Reading the logs

The entrypoint prints a startup line, a connectivity preflight, and the
agent's own output. A healthy start looks like:

```
[nezha ...] server=panel.example.com:8008 secret_len=32 tls=true
[nezha ...] config_path=/data/nezha-agent-config.yml
[nezha ...] preflight: panel.example.com:8008 reachable (HTTP 404)
[nezha ...] starting agent (attempt 1)
I: ... Connection to panel.example.com:8008 established
```

An HTTP status other than 200 on the preflight is fine — the gRPC port
answers HTTP with an error, which still proves the port is open.

Common problems:

| Symptom | Cause |
| --- | --- |
| `preflight: ... NOT reachable` | Wrong `NZ_SERVER`, or the panel's gRPC port is not exposed |
| `FATAL: NZ_SERVER is not set` | Environment variable missing in the dashboard |
| Agent starts but the panel shows nothing | The client secret does not match the entry on the panel |
| The node appears twice in the panel | `/data` was not mounted, so the UUID was regenerated |

## Security notes

- `NZ_DISABLE_COMMAND_EXECUTE` defaults to `true`. The panel can otherwise
  instruct the agent to run shell commands, which on a shared host would give
  another account remote code execution. Enable it only if you trust every
  operator of the panel.
- `NZ_DISABLE_AUTO_UPDATE` and `NZ_DISABLE_FORCE_UPDATE` default to `true`.
  The image is immutable and version-pinned; a self-update would try to
  replace the binary in a read-only filesystem.
- The client secret is stored in plaintext in `/data/nezha-agent-config.yml`
  (mode `0600`). The volume is private to the app, but treat that file as a
  secret and do not expose `/data` contents.
- Metrics that describe the container rather than the host
  (`NZ_SKIP_PROCS_COUNT`, `NZ_SKIP_CONNECTION_COUNT`) are skipped by
  default, because their values inside an isolated container are misleading.

## Upgrading the agent

Bump `NEZHA_AGENT_VERSION` in the `Dockerfile` and redeploy:

```dockerfile
ARG NEZHA_AGENT_VERSION=v2.3.5
```

The agent is pinned deliberately so that a rebuild does not silently change
the version. The upstream release notes are at
<https://github.com/nezhahq/agent/releases>.
