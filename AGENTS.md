# AGENTS.md

Kubernetes infra config for isolated AI coding tool environments (OpenCode, Claude Code, Codex CLI), deployed to the `ai` namespace. All images are Ubuntu 24.04 with database build deps. No application code, no tests, no lint.

Full user-facing docs are in `README.md`. This file covers what an agent would likely miss.

## File mapping

| Deploy script | YAML template | Pod name | Image |
|---------------|--------------|----------|-------|
| `oc-deploy.sh` | `oc-pod.yaml` | `oc-dev` | `oc-dev:1.0.1` |
| `oc-deploy-deployment.sh` | `oc-deployment.yaml` | `oc-dev-deployment-*` | `oc-dev:1.0.1` |
| `cc-deploy.sh` | `cc-pod.yaml` | `cc-dev` | `cc-dev:1.0.1` |
| `cc-deploy-deployment.sh` | `cc-deployment.yaml` | `cc-dev-deployment-*` | `cc-dev:1.0.1` |
| `codex-deploy.sh` | `codex-pod.yaml` | `codex-dev` | `codex-dev:1.0.1` |
| `codex-deploy-deployment.sh` | `codex-deployment.yaml` | `codex-dev-deployment-*` | `codex-dev:1.0.1` |

## Build order

- **OpenCode**: must run `docker/oc/download.sh` **before** `build.sh` — downloads binary to `docker/oc/bin/` (gitignored). `download.sh` auto-detects arch and latest GitHub release version.
- **Claude Code / Codex CLI**: just `build.sh` (npm install happens in Dockerfile).
- `build.sh` auto-detects host UID/GID for `hostPath` volume access — different user cloning? Just rebuild.
- Append `clean` to `build.sh` for no-cache build.

## Deploy scripts

**Pod scripts**: `{apply|delete|status}`
**Deployment scripts**: `{apply|delete|status|scale N}`

All scripts: `AI_K8S_HOME` defaults to script directory → `envsubst` resolves `${VAR}` in YAML → `kubectl apply -f -` from stdin.

**Never `kubectl apply` YAML files directly** — they contain unresolved `${VAR}` placeholders.

### Required env vars

| Tool | Required | Defaults |
|------|----------|----------|
| OpenCode | — | `OC_REPLICAS=3` |
| Claude Code | `ANTHROPIC_AUTH_TOKEN` | `CC_SONNET_MODEL=glm-5.1`, `CC_OPUS_MODEL=glm-5.1`, `CC_HAIKU_MODEL=glm-5.1`, `CC_REPLICAS=3` |
| Codex CLI | `CODEX_API_KEY` | `CODEX_MODEL=GLM-5.1`, `CODEX_REPLICAS=3` |

## Codex CCX sidecar

Codex CLI (Rust) only supports OpenAI Responses API, but Zhipu GLM only supports Chat Completions. CCX sidecar in the same pod handles translation: `Codex CLI → localhost:3000 (CCX) → Zhipu GLM`.

- `PROXY_ACCESS_KEY` = `${CODEX_API_KEY}` (same key for CCX auth and Zhipu upstream)
- `ENABLE_WEB_UI=false` in YAML — first-time channel setup requires temporarily setting `true` and re-applying
- Deploy scripts auto-generate `codex-cache/codex/config.toml` on each `apply` — **manual edits are lost**
- Three profiles switchable at runtime: `codex --config profile=glm-5-turbo`

## Gotchas

- **`download.sh` is slow in China**: use `https_proxy=http://127.0.0.1:7890 ./download.sh`
- **macOS users need `envsubst`**: `brew install gettext` (pre-installed on most Linux distros)
- **TLS verification disabled**: `NODE_TLS_REJECT_UNAUTHORIZED=0` in all Dockerfiles — intentional
- **`POSTGRES_PASSWORD=secret` in OC manifests**: boilerplate, not used by OpenCode itself
- **Shared `k8s-work/` volume**: all three tools mount the same directory — use separate git repos or subdirectories per project to avoid conflicts
- **`k8s-work/` causes `git add -A` to fail** (empty untracked dir with no commits) — add files explicitly: `git add <specific-files>`
- **CCX first-time setup required**: Codex pods need one-time channel configuration; config persists in `codex-cache/ccx/`
- **Deployment replicas share hostPath volumes**: for per-pod isolation, use PVC with StatefulSet
- **Runtime data dirs are gitignored** (`oc-cache/*`, `cc-cache/*`, `codex-cache/*`, `k8s-work/*`), preserved by `.gitkeep`
