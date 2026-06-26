# aicoding-k8s

Kubernetes isolation environments for AI coding assistants — **OpenCode**, **Claude Code**, and **Codex CLI** — all backed by [Zhipu GLM](https://open.bigmodel.cn) models.

Each tool runs as an isolated pod in the `ai` namespace with its own Docker image (Ubuntu 24.04 + database build deps). Config and state persist on the host via `hostPath` volumes. NodePort Services expose dev ports (5432, 5173, 8000, 8080, 80, 443) for each tool.

## Prerequisites

- Docker, kubectl, and git (macOS or Linux)
- [Zhipu API Key](https://open.bigmodel.cn) (for Claude Code)
- [cc-switch](https://github.com/farion1231/cc-switch) desktop app (for Codex CLI)
- `envsubst` — pre-installed on most Linux distros; macOS: `brew install gettext`

## Quick Start

```bash
git clone https://github.com/davidjiang0618/aicoding-k8s.git
cd aicoding-k8s
```

### 1. Build Images

| Tool | Image | Build Command |
|------|-------|---------------|
| OpenCode | `oc-dev:1.0.1` | `cd docker/oc && ./download.sh && ./build.sh` |
| Claude Code | `cc-dev:2.0.1` | `cd docker/cc && ./build.sh` |
| Codex CLI | `codex_cc-dev:1.0.1` | `cd docker/codex_cc && ./build.sh` |

> **OpenCode requires `download.sh` before `build.sh`** — it downloads the binary from GitHub Releases to `docker/oc/bin/` (gitignored). If the download is slow (e.g., in China), start a local proxy client (Clash/V2Ray, default port `7890`) first, then run: `https_proxy=http://127.0.0.1:7890 ./download.sh`

Append `clean` to any `build.sh` for a no-cache rebuild.

### 2. Set Your API Key

```bash
# For Claude Code
export ANTHROPIC_AUTH_TOKEN=your-zhipu-api-key

# For Codex CLI — no API key needed!
# Install and configure cc-switch on your host (see below).

# OpenCode requires no API key at deploy time (configured inside the container)
```

Get your key at [open.bigmodel.cn](https://open.bigmodel.cn).

### 3. Deploy

Each tool has two deploy modes:

| Mode | Script | Subcommands |
|------|--------|-------------|
| Single Pod | `{oc,cc,codex_cc}-deploy.sh` | `apply` `delete` `status` |
| Deployment (replicas) | `{oc,cc,codex_cc}-deploy-deployment.sh` | `apply` `delete` `status` `scale N` |

**OpenCode** (no API key needed):

```bash
# Single pod
./oc-deploy.sh apply

# Or deployment with 3 replicas (default)
./oc-deploy-deployment.sh apply

# Override replica count
OC_REPLICAS=5 ./oc-deploy-deployment.sh apply

# Scale an existing deployment
./oc-deploy-deployment.sh scale 2
```

**Claude Code**:

```bash
export ANTHROPIC_AUTH_TOKEN=your-zhipu-api-key

# Single pod
./cc-deploy.sh apply

# Deployment (default: 1 replica, glm-5.2 for all model slots)
./cc-deploy-deployment.sh apply

# Override model
CC_SONNET_MODEL=glm-4.7-flashx ./cc-deploy-deployment.sh apply
```

**Codex CLI** (no API key needed — cc-switch handles GLM auth):

```bash
# Single pod
./codex_cc-deploy.sh apply

# Deployment
./codex_cc-deploy-deployment.sh apply
```

> **Important**: Never `kubectl apply` the YAML files directly — they contain `${VAR}` placeholders resolved by the deploy scripts via `envsubst`.

### 4. Enter the Container

```bash
# Single pod
kubectl exec -it oc-dev -n ai -- bash

# Deployment (pick a pod from the list first)
kubectl get pods -l app=oc-dev -n ai
kubectl exec -it oc-dev-deployment-xxxxx -n ai -- bash
```

The working directory is `~/work` (mounted from `k8s-work/` on the host).

## Codex CLI Architecture (cc-switch)

Codex CLI only supports the OpenAI Responses API, but Zhipu GLM only supports Chat Completions. **cc-switch** (desktop app on the host) bridges this:

```
Codex CLI (container) → host.docker.internal:15721 (cc-switch proxy) → Zhipu GLM
```

### Prerequisites

1. Install [cc-switch](https://github.com/farion1231/cc-switch) on your Mac
2. Configure GLM provider preset in cc-switch (fill in your Zhipu API Key)
3. Enable proxy mode (Settings → Proxy → Enable Local Proxy, port 15721)

No API key in the deploy script — cc-switch manages GLM authentication. `CODEX_API_KEY` is set to a dummy value (`cc-switch-managed`) since Codex CLI requires the env var to exist.

### Switch Model at Runtime

```bash
codex --config profile=glm-4-6   # glm-4.6
codex --config profile=glm-4-5   # glm-4.5
codex --config profile=glm-5-1   # GLM-5.1 (default)
```

## NodePort Services

Each tool exposes 6 ports via NodePort:

| Tool | Port range | 5432 | 5173 | 8000 | 8080 | 80 | 443 |
|------|-----------|------|------|------|------|-----|-----|
| cc | 30xxx | 30543 | 30517 | 30800 | 30080 | 30000 | 30443 |
| oc | 31xxx | 31543 | 31517 | 31800 | 31080 | 31000 | 31443 |
| codex_cc | 32xxx | 32543 | 32517 | 32700 | 32080 | 32000 | 32443 |

Access via `<NodeIP>:<NodePort>`, e.g. `http://localhost:30517` for Claude Code's Vite dev server.

## Environment Variables

| Tool | Variable | Required | Default |
|------|----------|----------|---------|
| OpenCode | — | — | `OC_REPLICAS=3` |
| Claude Code | `ANTHROPIC_AUTH_TOKEN` | Yes | `CC_SONNET_MODEL=glm-5.2`, `CC_OPUS_MODEL=glm-5.2`, `CC_HAIKU_MODEL=glm-5.2`, `CC_REPLICAS=1` |
| Codex CLI | — (cc-switch manages auth) | — | `CODEX_MODEL=GLM-5.1`, `CC_SWITCH_PORT=15721`, `CODEX_CC_REPLICAS=3` |

## Notes

- **macOS users**: install `envsubst` via `brew install gettext` (pre-installed on most Linux distros).
- **cc-switch dependency**: Codex CLI pods cannot reach GLM if cc-switch is not running on the host with proxy enabled.
- **Shared workspace**: all three tools mount the same `k8s-work/` directory. Use separate git repos or subdirectories per project to avoid conflicts.
- **TLS disabled**: `NODE_TLS_REJECT_UNAUTHORIZED=0` in all images — for local dev only.
- **Deployment replicas share volumes**: for per-pod isolation, use PVC with StatefulSet.

## License

See [LICENSE](LICENSE).
