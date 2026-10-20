# cline.bot

A zero-dependency Node.js HTTP service, ready to deploy on [Deplexo](https://deplexo.com).

The repository currently ships a working service skeleton: a health endpoint, a
metadata endpoint, graceful shutdown, and the container/Dashboard configuration
needed to deploy it. Business logic can be added to `server.js` without
changing the deployment setup.

## Endpoints

| Method | Path | Response |
| --- | --- | --- |
| `GET` | `/` | Service name, version, start time, endpoint list |
| `GET` | `/healthz` | `{ "status": "ok", "uptime": <seconds> }` |
| `HEAD` | `/healthz` | Same headers, no body |
| any | other paths | `404` JSON |
| non-`GET`/`HEAD` | any | `405` JSON with `Allow: GET, HEAD` |

## Local development

```sh
npm test          # 6 tests, no network or Docker required
npm start         # listens on 0.0.0.0:3000 (override with PORT)
```

```sh
curl http://127.0.0.1:3000/healthz
# {"status":"ok","uptime":1.23}
```

There are no runtime dependencies, so there is no lockfile and no install step.
Adding a dependency means committing `package-lock.json` and adding an install
step to the Dockerfile (see [Docker and builds](#docker-and-builds)).

## Deploy to Deplexo

### 1. Connect a Git provider

Sign in at <https://deplexo.com>, then connect GitHub, GitLab, Bitbucket, or
Codeberg over OAuth and grant access to this repository. Private repositories
require the provider to be connected first.

### 2. Deploy from the dashboard

Open **Deploy**, choose the repository, and review the application name,
region, and resources. The form reads `deplexo.yaml` and marks the fields it
controls. Add any environment variables the app needs before submitting.

The app becomes reachable at `https://<app-name>.de.deplexo.com` once the
health check passes.

### 3. Or deploy from the terminal

```sh
curl -fsSL https://cli.deplexo.com/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

deplexo auth login
deplexo apps create --name cline-bot --repo https://github.com/weikkadd/cline.bot
deplexo link --app <APP_UUID>     # writes .deplexo.json in the current directory
deplexo deploy
deplexo deployments logs <DEPLOYMENT_UUID>
```

`deplexo deploy` returns as soon as the server accepts the request, so poll
`deployments logs` to see whether the build actually succeeded.

### 4. Or let an agent do it

The platform exposes an MCP server at `https://deplexo.com/mcp` (Streamable
HTTP + OAuth) with `deploy_app`, `redeploy_app`, `get_deployment`, and related
tools. The official guide for agents is at
<https://deplexo.com/agent.md>.

## Configuration

### `deplexo.yaml`

```yaml
version: 1
type: web

build:
  framework: dockerfile
  dockerfile: Dockerfile

run:
  port: 3000
```

The file lives at the repository root and must stay under 8 KiB. `version` and
`run.port` must be unquoted integers. Unknown fields are rejected.

`run.port` sets both the routed container port and the runtime `PORT`
environment variable, so the app does not need to hard-code a port.

> `type` is fixed when the app is created. If cline.bot becomes a background
> bot rather than an HTTP service, change it to `type: worker` and remove
> `run.port` **before** the first deployment — a web app cannot be converted
> into a worker afterwards.

### Docker and builds

The `Dockerfile` builds from `node:24-alpine`:

- Dependencies and executables are baked into the image. The runtime root
  filesystem is **read-only**, and neither `/tmp` nor `/data` allows execution,
  so downloading a binary at startup will not work.
- The container runs as the unprivileged `node` user with no added
  capabilities.
- `CMD` uses exec form (`["node", "server.js"]`) so the process receives
  `SIGTERM` directly and shuts down cleanly. The server handles `SIGTERM` and
  `SIGINT`, drains connections, and exits with code 0.

The app listens on `0.0.0.0`, not `localhost`, and the platform proxy only
routes to a port that a process is actually listening on. An `EXPOSE`
instruction alone does not make a service reachable.

### Environment variables

Set variables in the dashboard (**Settings → Environment**), not in
`deplexo.yaml`, since the YAML file is committed to the repository. Dashboard
values are encrypted at rest.

Environment variables are injected at **runtime only** and are not visible
during the build. A build that needs a runtime secret must be redesigned.

### Persistence

The container filesystem is read-only and is replaced on every deployment. For
state that must survive:

- `/tmp` — writable, 100 MB limit, disposable, cleared on restart.
- `/data` — a persistent volume per app, survives restarts and redeployments,
  removed when the app is deleted. Neither location allows execution.

Use `/data` for anything durable, and keep independent backups. A code
rollback does not restore data, undo a migration, or rotate secrets.

## Current limits of the platform

- One container per app. No Docker Compose, no multi-container stacks.
- No managed Postgres, MySQL, or Redis. Point the app at a hosted database and
  keep the credentials in environment variables.
- One instance per app. No autoscaling or load balancing.
- One region: EU (Germany).
- Rolling back rebuilds an earlier commit; it does not restore the database.
- Free tier: 1 app, 0.25 CPU, 128 MB RAM, 250 MB disk, 10 Mbit/s, 100 GB/month
  shared transfer.

## Project layout

```
.
├── deplexo.yaml        # Deplexo build and runtime configuration
├── Dockerfile          # node:24-alpine, non-root, exec-form CMD
├── .dockerignore       # keeps build context small and free of secrets
├── package.json        # no runtime dependencies; start and test scripts
├── server.js           # HTTP service and routing
└── test/
    ├── server.test.js  # endpoint behaviour
    └── lifecycle.test.js # startup and clean SIGTERM shutdown
```
