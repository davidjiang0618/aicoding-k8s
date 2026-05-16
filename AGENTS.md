# AGENTS.md

Kubernetes manifests and Docker images for isolated AI coding tool environments (OpenCode, Claude Code, Codex CLI), deployed to the `ai` namespace. All images are Ubuntu 24.04 with database build deps (PostgreSQL, Redis, etc.). No application code, no tests, no lint — this is purely infra config.

## Naming convention

Every file/script is prefixed by tool: `oc-` (OpenCode), `cc-` (Claude Code), `codex-` (Codex CLI). Docker images: `<prefix>-dev:1.0.1`.

## Build

```bash
cd docker/oc && ./download.sh && ./build.sh   # OpenCode: download binary first!
cd docker/cc && ./build.sh                     # Claude Code: installs via npm in Dockerfile
cd docker/codex && ./build.sh                  # Codex CLI: installs via npm in Dockerfile
```

- OpenCode requires running `docker/oc/download.sh` before `build.sh` — it downloads the binary to `docker/oc/bin/` (gitignored). Auto-detects arch and latest version.
- `build.sh` auto-detects host UID/GID via `$(id -u)`/`$(id -g)` and passes as `--build-arg` so container `postgres` user matches host user for `hostPath` volume access. Different user cloning the repo? Just rebuild.
- Append `clean` to `build.sh` for no-cache build.

## Deploy

6 deploy scripts: `{oc,cc,codex}-deploy.sh` (single pod), `{oc,cc,codex}-deploy-deployment.sh` (Deployment with replicas).

**Pod scripts**: `{apply|delete|status}`
**Deployment scripts**: `{apply|delete|status|scale N}`

```bash
./oc-deploy-deployment.sh apply                    # uses defaults
OC_REPLICAS=5 ./oc-deploy-deployment.sh apply      # override replicas
./oc-deploy-deployment.sh scale 2                  # scale without re-apply
```

All scripts follow the same pattern:
1. `AI_K8S_HOME` defaults to script directory (overridable)
2. `kubectl create namespace ai 2>/dev/null || true`
3. `mkdir -p` cache dirs
4. `envsubst` substitutes `${AI_K8S_HOME}` + tool env vars in YAML
5. `kubectl apply -f -` from stdin

YAML files are templates with `${VAR}` placeholders — **never `kubectl apply` them directly**, always use the deploy scripts.

### Required env vars

| Tool | Required | Defaults |
|------|----------|----------|
| OpenCode | — | `OC_REPLICAS=3` |
| Claude Code | `ANTHROPIC_AUTH_TOKEN` | `CC_SONNET_MODEL=glm-5.1`, `CC_OPUS_MODEL=glm-5.1`, `CC_HAIKU_MODEL=glm-5.1`, `CC_REPLICAS=3` |
| Codex CLI | `CODEX_API_KEY` | `CODEX_MODEL=GLM-5.1`, `CODEX_REPLICAS=3` |

### Codex config.toml

Deploy scripts auto-generate `codex-cache/codex/config.toml` on each `apply` — **manual edits are lost**. It configures:
- `model_provider = "ccx"` via CCX sidecar proxy at `http://localhost:3000/v1`
- Three profiles: `glm-5-1` (GLM-5.1, default), `glm-5-turbo` (GLM-5-Turbo), `glm-4-7-flashx` (GLM-4.7-FlashX)
- Switch at runtime: `codex --config profile=glm-5-turbo`

### Codex CCX sidecar

Codex CLI (Rust) only supports the OpenAI Responses API (`/v1/responses`), but Zhipu GLM only supports Chat Completions (`/v1/chat/completions`). A CCX sidecar container runs in the same pod:

```
Codex CLI → localhost:3000 (CCX) → Responses→Chat conversion → Zhipu GLM
```

- **Image**: `crpi-i19l8zl0ugidq97v.cn-hangzhou.personal.cr.aliyuncs.com/bene/ccx:latest`
- **Config persistence**: `codex-cache/ccx/` → `/app/.config` (hostPath)
- **Auth**: `PROXY_ACCESS_KEY` = `${CODEX_API_KEY}` (same key for CCX auth and Zhipu upstream)
- **Web UI is disabled** (`ENABLE_WEB_UI=false`). First-time channel setup: temporarily change to `true` in the YAML and re-apply, or configure CCX via its API directly. After initial setup, config persists in `codex-cache/ccx/` across pod restarts.

### Claude Code API

Uses Zhipu Anthropic-compatible API (`ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic`). All three model slots (sonnet/opus/haiku) default to `glm-5.1`.

## Volume mounts

| Host path | Container path | Tool |
|-----------|---------------|------|
| `oc-cache/{config,state,share,cache}` | `~/.config/opencode`, `~/.local/state/opencode`, `~/.local/share/opencode`, `~/.cache/opencode` | OpenCode |
| `cc-cache/claude` | `~/.claude` | Claude Code |
| `codex-cache/codex` | `~/.codex` | Codex CLI |
| `codex-cache/ccx` | `/app/.config` | Codex CCX sidecar |
| `k8s-work` | `~/work` | All (shared) |

## Gotchas

- **Host paths are macOS-specific**: volume mounts point under `/Users/david/ak/`. Not portable to Linux without changes.
- **TLS verification disabled**: `NODE_TLS_REJECT_UNAUTHORIZED=0` in all Dockerfiles — intentional for local dev.
- **All YAML paths use `${AI_K8S_HOME}`**: substituted via `envsubst` at deploy time, never hardcoded.
- **Codex config is overwritten on each `apply`**: `config.toml` is generated from deploy script, not a tracked file.
- **Shared `k8s-work` volume**: all three tools share the same working directory. Concurrent writes can conflict.
- **`.gitkeep` preserves dirs**: runtime data directories are gitignored (`oc-cache/*`, `cc-cache/*`, `codex-cache/*`, `k8s-work/*`).
- **CCX first-time setup required**: Codex pods need a one-time CCX channel configuration before use. Config persists in `codex-cache/ccx/`.
- **Deployment replicas share hostPath volumes**: if isolated storage per pod is needed, use PVC with StatefulSet instead (noted in deployment YAMLs).
