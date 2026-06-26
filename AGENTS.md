# AGENTS.md

Kubernetes infra config for isolated AI coding tool environments (OpenCode, Claude Code, Codex CLI), deployed to the `ai` namespace. All images are Ubuntu 24.04 with database build deps. No application code, no tests, no lint.

Full user-facing docs are in `README.md`. This file covers what an agent would likely miss.

## File mapping

| Deploy script | YAML templates | Pod name | Image |
|---------------|---------------|----------|-------|
| `oc-deploy.sh` | `oc-pod.yaml`, `oc-service.yaml` | `oc-dev` | `oc-dev:1.0.1` |
| `oc-deploy-deployment.sh` | `oc-deployment.yaml`, `oc-service.yaml` | `oc-dev-deployment-*` | `oc-dev:1.0.1` |
| `cc-deploy.sh` | `cc-pod.yaml`, `cc-service.yaml` | `cc-dev` | `cc-dev:2.0.1` |
| `cc-deploy-deployment.sh` | `cc-deployment.yaml`, `cc-service.yaml` | `cc-dev-deployment-*` | `cc-dev:2.0.1` |
| `codex_cc-deploy.sh` | `codex_cc-pod.yaml`, `codex_cc-service.yaml` | `codex-cc-dev` | `codex_cc-dev:1.0.1` |
| `codex_cc-deploy-deployment.sh` | `codex_cc-deployment.yaml`, `codex_cc-service.yaml` | `codex-cc-dev-deployment-*` | `codex_cc-dev:1.0.1` |

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
| Claude Code | `ANTHROPIC_AUTH_TOKEN` | `CC_SONNET_MODEL=glm-5.2`, `CC_OPUS_MODEL=glm-5.2`, `CC_HAIKU_MODEL=glm-5.2`, `CC_REPLICAS=1` |
| Codex CLI (codex_cc) | — (cc-switch manages GLM auth) | `CODEX_MODEL=GLM-5.1`, `CC_SWITCH_PORT=15721`, `CODEX_CC_REPLICAS=3` |

## NodePort allocation

| Tool | Port range | 5432 | 5173 | 8000 | 8080 | 80 | 443 |
|------|-----------|------|------|------|------|-----|-----|
| cc | 30xxx | 30543 | 30517 | 30800 | 30080 | 30000 | 30443 |
| oc | 31xxx | 31543 | 31517 | 31800 | 31080 | 31000 | 31443 |
| codex_cc | 32xxx | 32543 | 32517 | 32700 | 32080 | 32000 | 32443 |

Valid NodePort range is **30000-32767**. When adding new tools, pick the next free range.

## Codex CLI architecture (codex_cc)

Codex CLI only supports OpenAI Responses API, but Zhipu GLM only supports Chat Completions. **cc-switch** (desktop app running on the macOS host) bridges this:

```
Codex CLI (container) → host.docker.internal:15721 (cc-switch proxy) → Zhipu GLM
```

- **cc-switch must be running on the host** with proxy enabled and GLM provider configured
- No API key needed in deploy script — cc-switch manages GLM authentication
- `CODEX_API_KEY` is set to dummy value `cc-switch-managed` (Codex CLI requires the env var to exist)
- Deploy scripts auto-generate `codex_cc-cache/codex/config.toml` on each `apply` — **manual edits are lost**
- Profiles switchable at runtime: `codex --config profile=glm-4-6`

## Gotchas

- **`download.sh` is slow in China**: start a local proxy client (Clash/V2Ray, default port `7890`) first, then run `https_proxy=http://127.0.0.1:7890 ./download.sh`
- **macOS users need `envsubst`**: `brew install gettext` (pre-installed on most Linux distros)
- **TLS verification disabled**: `NODE_TLS_REJECT_UNAUTHORIZED=0` in all Dockerfiles — intentional
- **`POSTGRES_PASSWORD=secret` in OC manifests**: boilerplate, not used by OpenCode itself
- **Shared `k8s-work/` volume**: all three tools mount the same directory — use separate git repos or subdirectories per project to avoid conflicts
- **`k8s-work/` causes `git add -A` to fail** (empty untracked dir with no commits) — add files explicitly: `git add <specific-files>`
- **Deployment replicas share hostPath volumes**: for per-pod isolation, use PVC with StatefulSet
- **Runtime data dirs are gitignored** (`oc-cache/*`, `cc-cache/*`, `codex_cc-cache/*`, `k8s-work/*`), preserved by `.gitkeep`
- **cc-switch host dependency**: codex_cc pods cannot reach GLM if cc-switch is not running on the host
