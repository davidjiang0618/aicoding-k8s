# Running AI Coding Agents on Kubernetes: The aicoding-k8s Project

> Source: https://github.com/davidjiang0618/aicoding-k8s

## The Rise of AI Coding Agents

AI coding agents are no longer experimental curiosities — they are becoming integral to how software gets built. Tools like OpenCode, Claude Code, and OpenAI's Codex CLI can read entire codebases, write and refactor code, run tests, and execute shell commands, all within an autonomous loop. A developer describes a task, and the agent plans, implements, and verifies the solution.

But as these tools move from personal experiments to team-scale usage, a new set of infrastructure challenges emerges:

**Security isolation.** AI coding agents have the ability to read and write files and execute arbitrary commands. Running them directly on a developer's laptop means a misinterpreted instruction or a hallucinated `rm -rf` can destroy local state. Worse, if an agent pulls and executes untrusted code, the host machine is fully exposed. Teams need a boundary between the agent's workspace and the developer's machine.

**Multi-tool concurrency.** Different agents excel at different tasks. OpenCode is a lightweight, local-first coding assistant. Claude Code is renowned for deep code understanding and multi-file refactoring. Codex CLI is designed for autonomous, multi-step task execution. Teams want to run multiple agents simultaneously, each working on different projects, without interference.

**Model compatibility.** These tools were built around Western LLM providers — Anthropic for Claude Code, OpenAI for Codex CLI. But users in China and other regions increasingly prefer domestic models like Zhipu GLM, which offer competitive performance with lower latency and better data sovereignty. Bridging the protocol gap between agent tooling and alternative model providers is a non-trivial engineering challenge.

**Scalability.** A single developer needs one agent instance. A team of ten might need twenty parallel sessions across different repositories. Scaling from one Pod to a replicated Deployment should be a single command, not a re-architecture.

**aicoding-k8s** is an open-source project that addresses all four challenges. It provides production-ready Kubernetes configurations to containerize and isolate three major AI coding agents, seamlessly connect them to Zhipu GLM models, and scale them from a single Pod to a multi-replica Deployment.

## What is aicoding-k8s?

aicoding-k8s is a Kubernetes infrastructure project that packages OpenCode, Claude Code, and Codex CLI into isolated, containerized environments deployed to a dedicated `ai` namespace. Each tool runs inside its own Docker image (Ubuntu 24.04 with database build dependencies pre-installed), connects to Zhipu GLM models for AI capabilities, and persists its configuration and state via `hostPath` volume mounts.

The project delivers three core values:

1. **Isolation by default.** Each agent runs in its own Pod with its own filesystem, user namespace, and resource limits. The host machine is protected — agents can only see what's mounted into their container. Multiple agents can run concurrently without stepping on each other.

2. **Transparent model adaptation.** Claude Code talks to Zhipu GLM via an Anthropic-compatible API endpoint with zero code changes. Codex CLI uses a CCX sidecar proxy that translates the OpenAI Responses API to Chat Completions in real time. OpenCode is configured directly inside the container. From the agent's perspective, nothing is different — it just works.

3. **Operational simplicity.** Build images, set an API key, run a deploy script. That's the entire workflow. Scaling from one replica to five is a single command. Teardown is equally simple. No Helm charts, no CRDs, no operators — just shell scripts, YAML templates, and `envsubst`.

## Architecture Overview

### Project Structure

```
aicoding-k8s/
├── docker/
│   ├── oc/          # OpenCode image (pre-downloaded binary)
│   ├── cc/          # Claude Code image (npm install)
│   └── codex/       # Codex CLI image (npm install)
├── oc-*.sh / oc-*.yaml        # OpenCode deploy scripts and templates
├── cc-*.sh / cc-*.yaml        # Claude Code deploy scripts and templates
├── codex-*.sh / codex-*.yaml  # Codex CLI deploy scripts and templates
├── k8s-work/                   # Shared workspace (hostPath mount)
├── {oc,cc,codex}-cache/        # Per-tool persistent data
├── AGENTS.md                   # AI agent operations guide
└── README.md                   # User documentation
```

### Two Deployment Modes

Each tool supports two deployment modes, selectable via script:

| Mode | Script Pattern | Use Case |
|------|---------------|----------|
| **Single Pod** | `{tool}-deploy.sh` | Individual developer, debugging, testing |
| **Deployment** | `{tool}-deploy-deployment.sh` | Team usage, parallel sessions, scale-out |

The single Pod mode creates exactly one Pod — straightforward for personal use. The Deployment mode creates a Kubernetes Deployment with a configurable replica count (default: 3), enabling multiple parallel agent sessions. Scaling is done via `./cc-deploy-deployment.sh scale 5` at runtime.

### Container Design

All three images share a common foundation:

- **Base OS:** Ubuntu 24.04
- **Build dependencies:** `bison`, `flex`, `cmake`, `gcc`, `g++`, `gdb`, `zlib1g-dev`, `libreadline-dev` — pre-installed for database and systems programming
- **Non-root user:** A `postgres` user is created with the host's UID/GID (passed as build args), ensuring `hostPath` volume permissions work correctly
- **Shared workspace:** `~/work` inside the container maps to `k8s-work/` on the host, giving agents access to source code

The UID/GID matching is critical. Docker containers typically run as root or a fixed-UID user, but `hostPath` mounts retain the host's filesystem permissions. The `build.sh` scripts auto-detect the current user's UID and GID and pass them as `--build-arg`, so the container's `postgres` user has exactly the same permissions as the host user who built the image. Clone the repo on a different machine? Just rebuild.

## Model Adaptation: The Hard Problem

The most technically interesting part of this project is how each agent connects to Zhipu GLM. The three tools use fundamentally different API protocols, and GLM supports different subsets. Here is how each gap is bridged.

### Claude Code: Zero-Modification API Compatibility

Claude Code natively uses the Anthropic API protocol. Zhipu GLM provides an Anthropic-compatible endpoint at:

```
https://open.bigmodel.cn/api/anthropic
```

The adaptation requires exactly one line in the Dockerfile:

```dockerfile
ENV ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
```

Claude Code supports three model slots — Sonnet, Opus, and Haiku — each typically mapped to a different Anthropic model. In aicoding-k8s, all three slots default to `glm-5.1` but can be overridden independently:

```bash
CC_SONNET_MODEL=glm-5.1
CC_OPUS_MODEL=glm-5.1
CC_HAIKU_MODEL=glm-5.1
```

This works because Zhipu's Anthropic-compatible layer faithfully implements the full Anthropic API surface — streaming, tool use, multi-turn conversations. Claude Code is completely unaware it is talking to a non-Anthropic model.

Claude Code's conversation history and settings persist via a `hostPath` mount: the `cc-cache/claude/` directory on the host maps to `~/.claude` inside the container, preserving data across Pod restarts.

### OpenCode: In-Container Configuration

OpenCode takes a different approach. Rather than requiring API keys at deploy time, OpenCode's configuration is managed entirely inside the container. The user enters the container, runs `opencode`, and configures the model provider interactively.

To ensure configuration survives Pod restarts, four directories are mounted via `hostPath`:

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `oc-cache/config` | `~/.config/opencode` | Configuration files |
| `oc-cache/state` | `~/.local/state/opencode` | Runtime state |
| `oc-cache/share` | `~/.local/share/opencode` | Shared data |
| `oc-cache/cache` | `~/.cache/opencode` | Cache |

These are set via OpenCode's environment variables (`OC_CONFIG_HOME`, `OC_STATE_HOME`, etc.), each mapped to a `subPath` mount from the host's `oc-cache/` directory. Once configured, the setup persists across Pod deletions and recreations.

### Codex CLI: CCX Sidecar Protocol Translation

This is the most complex adaptation. Codex CLI, written in Rust, **only supports the OpenAI Responses API** (`POST /v1/responses`). Zhipu GLM **only supports the Chat Completions API** (`POST /v1/chat/completions`). These are completely different protocols:

```
OpenAI Responses API:   { input, instructions, tools, ... }
Chat Completions API:   { messages, model, temperature, ... }
```

The project solves this with a **CCX sidecar container** — a lightweight protocol translation gateway ([CCX](https://github.com/songquanpeng/ccx)) deployed alongside Codex CLI in the same Pod:

```
┌─────────────────────────────────────────────────┐
│                     Pod                          │
│                                                  │
│  ┌───────────┐         ┌──────────────────┐     │
│  │ Codex CLI  │         │   CCX Sidecar    │     │
│  │            │         │                  │     │
│  │  Sends     │────────>│  Translates      │     │
│  │  Responses │         │  Responses →     │     │
│  │  API format│         │  Chat Completions│─────┼──> Zhipu GLM
│  │            │<────────│                  │     │
│  │  Receives  │         │  Reverse-converts│     │
│  │  response  │         │  response body   │     │
│  └───────────┘         └──────────────────┘     │
│                                                  │
│    localhost:3000        PROXY_ACCESS_KEY        │
└─────────────────────────────────────────────────┘
```

**How it works step by step:**

1. The deploy script generates `~/.codex/config.toml` that points Codex CLI to `http://localhost:3000/v1` as its model provider
2. Codex CLI sends a Responses API request to `localhost:3000`
3. CCX receives the request and translates it from Responses format to Chat Completions format
4. CCX forwards the translated request to Zhipu GLM's API
5. Zhipu GLM returns a Chat Completions response
6. CCX reverse-translates the response back to Responses format and returns it to Codex CLI

The sidecar pattern is essential here — both containers share the same network namespace, so Codex CLI can reach CCX via `localhost`. The same API key (`CODEX_API_KEY`) serves dual purpose: authenticating Codex CLI to CCX (`PROXY_ACCESS_KEY`) and authenticating CCX to Zhipu GLM upstream.

**Auto-generated configuration.** The deploy script creates `config.toml` on every `apply` with three model profiles:

```toml
model = "GLM-5.1"
model_provider = "ccx"

[model_providers.ccx]
name = "CCX Proxy"
base_url = "http://localhost:3000/v1"
env_key = "CODEX_API_KEY"

[profiles.glm-5-turbo]
model = "GLM-5-Turbo"

[profiles.glm-4-7-flashx]
model = "GLM-4.7-FlashX"

[profiles.glm-5-1]
model = "GLM-5.1"
```

Inside the container, switching models at runtime requires no redeployment:

```bash
codex --config profile=glm-5-turbo     # Use GLM-5-Turbo
codex --config profile=glm-4-7-flashx  # Use GLM-4.7-FlashX
codex --config profile=glm-5-1         # Back to default GLM-5.1
```

**One-time CCX channel setup.** After the first deployment, CCX needs to be configured with a Responses channel pointing to Zhipu GLM's endpoint (`https://open.bigmodel.cn/api/paas/v4/`). This is done by:

1. Set `ENABLE_WEB_UI=true` in `codex-pod.yaml` or `codex-deployment.yaml`
2. Re-apply: `./codex-deploy.sh apply`
3. Port-forward: `kubectl port-forward codex-dev 3000:3000 -n ai`
4. Open `http://localhost:3000` in a browser and add a **Responses** channel with the Zhipu GLM endpoint URL and your API key
5. Set `ENABLE_WEB_UI=false` and re-apply to close the web UI

The channel configuration persists in `codex-cache/ccx/` across Pod restarts. This step only needs to be done once per host.

## Getting Started

### Prerequisites

- Docker, kubectl, and git (macOS or Linux)
- A [Zhipu API Key](https://open.bigmodel.cn) (required for Claude Code and Codex CLI)
- `envsubst` — pre-installed on most Linux distributions; macOS users: `brew install gettext`

### Step 1: Clone the Repository

```bash
git clone https://github.com/davidjiang0618/aicoding-k8s.git
cd aicoding-k8s
```

### Step 2: Build Images

Each tool has its own Docker image, built from the `docker/<tool>/` directory:

```bash
# OpenCode — download binary first, then build
cd docker/oc
./download.sh       # Auto-detects arch and latest GitHub release
./build.sh          # Builds oc-dev:1.0.1

# Claude Code — direct build (npm install in Dockerfile)
cd docker/cc
./build.sh          # Builds cc-dev:1.0.1

# Codex CLI — direct build (npm install in Dockerfile)
cd docker/codex
./build.sh          # Builds codex-dev:1.0.1
```

Append `clean` to any `build.sh` for a no-cache rebuild. The build scripts auto-detect your host UID/GID — no manual configuration needed.

> **Note for users in China:** `download.sh` fetches the OpenCode binary from GitHub Releases, which may be slow. Use a proxy: `https_proxy=http://127.0.0.1:7890 ./download.sh`

### Step 3: Set Your API Key

```bash
# For Claude Code
export ANTHROPIC_AUTH_TOKEN=your-zhipu-api-key

# For Codex CLI
export CODEX_API_KEY=your-zhipu-api-key

# OpenCode requires no API key at deploy time
```

### Step 4: Deploy

Each tool has a dedicated deploy script. The script creates the `ai` namespace, sets up cache directories, resolves variables in the YAML template, and submits the result to Kubernetes:

```bash
# Single pod
./cc-deploy.sh apply

# Deployment with 3 replicas (default)
./cc-deploy-deployment.sh apply

# Custom replica count
CC_REPLICAS=5 ./cc-deploy-deployment.sh apply

# Scale an existing deployment at runtime
./cc-deploy-deployment.sh scale 2
```

> **Important:** Never run `kubectl apply -f cc-pod.yaml` directly. The YAML files contain `${VAR}` placeholders that are resolved by the deploy scripts via `envsubst`.

### Step 5: Enter the Container

```bash
# List running pods
kubectl get pods -n ai

# Enter a single pod
kubectl exec -it cc-dev -n ai -- bash

# Enter a deployment pod (pick from the list first)
kubectl exec -it cc-dev-deployment-xxxxx -n ai -- bash
```

The working directory is `~/work`, which maps to `k8s-work/` on the host. Files are synced in real time between host and container. All three tools share this workspace — use separate git repositories or subdirectories to avoid conflicts.

## Under the Hood: Deploy Script Design

All deploy scripts follow a consistent pattern built around `envsubst`, the GNU utility for substituting environment variables in text:

```bash
#!/bin/bash
# 1. Determine project root
export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}

# 2. Set tool-specific variables with defaults
export CC_SONNET_MODEL=${CC_SONNET_MODEL:-glm-5.1}
export CC_OPUS_MODEL=${CC_OPUS_MODEL:-glm-5.1}
export CC_HAIKU_MODEL=${CC_HAIKU_MODEL:-glm-5.1}

# 3. Resolve all ${VAR} placeholders in the YAML template
YAML=$(envsubst < cc-pod.yaml)

# 4. Submit resolved YAML to kubectl via stdin
echo "$YAML" | kubectl apply -f -
```

This design has several deliberate properties:

**YAML templates are not final artifacts.** The template files contain `${ANTHROPIC_AUTH_TOKEN}`, `${AI_K8S_HOME}`, and other placeholders that only exist at runtime. This prevents accidental deployment with unresolved variables and keeps secrets out of version-controlled YAML files.

**Stdin piping, not file writing.** The resolved YAML is piped directly to `kubectl apply` via stdin rather than written to an intermediate file. This avoids leaving plaintext API keys on the host filesystem. (Note: the Kubernetes API server does store the Pod spec in etcd; for production use, consider Kubernetes Secrets with encryption at rest.)

**Overridable project root.** `AI_K8S_HOME` defaults to the script's directory but can be overridden via environment variable, supporting non-standard installation paths.

**Auto-provisioning dependencies.** The `apply` command creates the `ai` namespace (idempotently) and all required cache directories before submitting the Pod spec. No manual setup steps are needed.

**Subcommand pattern.** All scripts expose `apply`, `delete`, and `status` subcommands. Deployment scripts add `scale N`. This consistency reduces cognitive overhead when switching between tools.

## Conclusion

aicoding-k8s solves the practical infrastructure challenges that emerge when AI coding agents move from individual experimentation to team-scale deployment:

1. **Security isolation** through Kubernetes Pod boundaries — each agent runs in its own container with its own filesystem, protecting the host machine and enabling multi-agent concurrency.

2. **Seamless model adaptation** through protocol compatibility — Claude Code uses Zhipu's Anthropic-compatible endpoint with zero code changes, while Codex CLI leverages a CCX sidecar for real-time Responses-to-Chat Completions translation.

3. **Operational simplicity** through shell-script-driven deployment — build, configure, deploy, and scale with familiar commands. No complex abstractions, no additional controllers.

The project is open source at https://github.com/davidjiang0618/aicoding-k8s. Contributions and feedback are welcome.
