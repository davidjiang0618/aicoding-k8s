# aicoding-k8s

Kubernetes isolation environments for AI coding assistants — **OpenCode**, **Claude Code**, and **Codex CLI** — all backed by [Zhipu GLM](https://open.bigmodel.cn) models.

Each tool runs as an isolated pod in the `ai` namespace with its own Docker image (Ubuntu 24.04 + database build deps). Config and state persist on the host via `hostPath` volumes.

## Prerequisites

- Docker, kubectl, and git (macOS or Linux)
- [Zhipu API Key](https://open.bigmodel.cn) (for Claude Code and Codex CLI)
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
| Claude Code | `cc-dev:1.0.1` | `cd docker/cc && ./build.sh` |
| Codex CLI | `codex-dev:1.0.1` | `cd docker/codex && ./build.sh` |

> **OpenCode requires `download.sh` before `build.sh`** — it downloads the binary from GitHub Releases to `docker/oc/bin/` (gitignored). If the download is slow, set a proxy: `https_proxy=http://127.0.0.1:7890 ./download.sh`

Append `clean` to any `build.sh` for a no-cache rebuild.

### 2. Set Your API Key

```bash
# For Claude Code
export ANTHROPIC_AUTH_TOKEN=your-zhipu-api-key

# For Codex CLI
export CODEX_API_KEY=your-zhipu-api-key

# OpenCode requires no API key at deploy time (configured inside the container)
```

Get your key at [open.bigmodel.cn](https://open.bigmodel.cn).

### 3. Deploy

Each tool has two deploy modes:

| Mode | Script | Subcommands |
|------|--------|-------------|
| Single Pod | `{oc,cc,codex}-deploy.sh` | `apply` `delete` `status` |
| Deployment (replicas) | `{oc,cc,codex}-deploy-deployment.sh` | `apply` `delete` `status` `scale N` |

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

# Deployment (default: 3 replicas, glm-5.1 for all model slots)
./cc-deploy-deployment.sh apply

# Override model
CC_SONNET_MODEL=glm-4.7-flashx ./cc-deploy-deployment.sh apply
```

**Codex CLI**:

```bash
export CODEX_API_KEY=your-zhipu-api-key

# Single pod
./codex-deploy.sh apply

# Deployment
./codex-deploy-deployment.sh apply
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

## Codex CCX Sidecar

Codex CLI (Rust) only supports the OpenAI Responses API, but Zhipu GLM only supports Chat Completions. A CCX sidecar container handles protocol translation:

```
Codex CLI → localhost:3000 (CCX) → Responses→Chat → Zhipu GLM
```

### First-time CCX Setup

After the first `apply`, configure the CCX channel:

1. Set `ENABLE_WEB_UI=true` in `codex-pod.yaml` or `codex-deployment.yaml`
2. Re-apply: `./codex-deploy.sh apply`
3. Port-forward: `kubectl port-forward codex-dev 3000:3000 -n ai`
4. Open http://localhost:3000 and add a **Responses** channel pointing to Zhipu GLM
5. Set `ENABLE_WEB_UI=false` and re-apply

CCX config persists in `codex-cache/ccx/` across pod restarts.

### Switch Model at Runtime

```bash
codex --config profile=glm-5-turbo     # GLM-5-Turbo
codex --config profile=glm-4-7-flashx  # GLM-4.7-FlashX
codex --config profile=glm-5-1         # GLM-5.1 (default)
```

## Environment Variables

| Tool | Variable | Required | Default |
|------|----------|----------|---------|
| OpenCode | — | — | `OC_REPLICAS=3` |
| Claude Code | `ANTHROPIC_AUTH_TOKEN` | Yes | `CC_SONNET_MODEL=glm-5.1`, `CC_OPUS_MODEL=glm-5.1`, `CC_HAIKU_MODEL=glm-5.1`, `CC_REPLICAS=3` |
| Codex CLI | `CODEX_API_KEY` | Yes | `CODEX_MODEL=GLM-5.1`, `CODEX_REPLICAS=3` |

## Notes

- **macOS users**: install `envsubst` via `brew install gettext` (pre-installed on most Linux distros).
- **Shared workspace**: all three tools mount the same `k8s-work/` directory. Use separate git repos or subdirectories per project to avoid conflicts.
- **TLS disabled**: `NODE_TLS_REJECT_UNAUTHORIZED=0` in all images — for local dev only.
- **Deployment replicas share volumes**: for per-pod isolation, use PVC with StatefulSet.

## License

See [LICENSE](LICENSE).
