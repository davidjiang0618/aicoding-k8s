# 在 Kubernetes 上运行 AI 编码助手：aicoding-k8s 项目介绍

> 原文地址：https://github.com/davidjiang0618/aicoding-k8s

## AI 编码助手的崛起

AI 编码助手不再是实验性的玩具——它们正在成为软件构建方式中不可或缺的一部分。OpenCode、Claude Code 和 OpenAI 的 Codex CLI 等工具能够在自主循环中读取整个代码库、编写和重构代码、运行测试、执行 Shell 命令。开发者描述一个任务，助手就会规划、实现并验证解决方案。

然而，当这些工具从个人实验走向团队级使用时，一系列新的基础设施挑战随之而来：

**安全隔离。** AI 编码助手拥有文件读写和执行任意命令的能力。让它们直接运行在开发者的笔记本电脑上，意味着一条被误读的指令或一次幻觉产生的 `rm -rf` 就可以摧毁本地状态。更糟的是，如果助手拉取并执行了不受信任的代码，主机将完全暴露。团队需要在助手的工作空间与开发者的机器之间建立边界。

**多工具并行。** 不同的助手擅长不同的任务。OpenCode 是一个轻量级、本地优先的编码助手。Claude Code 以深度代码理解和多文件重构能力著称。Codex CLI 则专为自主多步骤任务执行而设计。团队希望能同时运行多个助手，各自处理不同项目，互不干扰。

**模型兼容性。** 这些工具围绕西方 LLM 提供商构建——Claude Code 对应 Anthropic，Codex CLI 对应 OpenAI。但中国和其他地区的用户越来越倾向于使用智谱 GLM 等国产模型，它们提供有竞争力的性能、更低的延迟和更好的数据主权保障。弥合助手工具与替代模型提供商之间的协议鸿沟，是一个非平凡的工程挑战。

**可扩展性。** 单个开发者需要一个助手实例。一个十人团队可能需要二十个并行会话，跨不同代码仓库运行。从单 Pod 扩展到多副本 Deployment 应该是一条命令的事，而不是一次架构重构。

**aicoding-k8s** 是一个开源项目，旨在解决上述全部四个挑战。它提供生产就绪的 Kubernetes 配置，将三大 AI 编码助手容器化和隔离化，无缝连接到智谱 GLM 模型，并支持从单 Pod 扩展到多副本 Deployment。

## aicoding-k8s 是什么？

aicoding-k8s 是一个 Kubernetes 基础设施项目，将 OpenCode、Claude Code 和 Codex CLI 打包到隔离的容器化环境中，部署到专用的 `ai` 命名空间。每个工具运行在自己的 Docker 镜像中（基于 Ubuntu 24.04，预装数据库编译依赖），通过智谱 GLM 模型提供 AI 能力，并通过 `hostPath` 卷挂载持久化配置和状态。

项目交付三大核心价值：

1. **默认隔离。** 每个助手运行在独立的 Pod 中，拥有独立的文件系统、用户命名空间和资源限制。主机受到保护——助手只能看到挂载到容器中的内容。多个助手可以并行运行，互不干扰。

2. **透明的模型适配。** Claude Code 通过 Anthropic 兼容的 API 端点连接智谱 GLM，零代码修改。Codex CLI 通过运行在宿主机上的 cc-switch 代理连接，实时将 OpenAI Responses API 转换为 Chat Completions。OpenCode 直接在容器内配置。从助手的角度来看，一切如常——它只是正常工作。

3. **运维简便。** 构建镜像、设置 API Key、运行部署脚本——这就是全部工作流。从一个副本扩展到五个只需要一条命令。销毁同样简单。没有 Helm Chart、没有 CRD、没有 Operator——只有 Shell 脚本、YAML 模板和 `envsubst`。

## 架构概览

### 项目结构

```
aicoding-k8s/
├── docker/
│   ├── oc/          # OpenCode 镜像（预下载二进制）
│   ├── cc/          # Claude Code 镜像（npm 安装）
│   └── codex_cc/    # Codex CLI 镜像（npm 安装）
├── oc-*.sh / oc-*.yaml              # OpenCode 部署脚本和模板
├── cc-*.sh / cc-*.yaml              # Claude Code 部署脚本和模板
├── codex_cc-*.sh / codex_cc-*.yaml  # Codex CLI 部署脚本和模板
├── k8s-work/                         # 共享工作目录（hostPath 挂载）
├── {oc,cc,codex_cc}-cache/          # 各工具的持久化数据
├── AGENTS.md                         # AI 代理操作指南
└── README.md                         # 使用文档
```

### 两种部署模式

每个工具支持两种部署模式，通过脚本选择：

| 模式 | 脚本模式 | 适用场景 |
|------|---------|---------|
| **单 Pod** | `{tool}-deploy.sh` | 个人开发、调试、测试 |
| **Deployment** | `{tool}-deploy-deployment.sh` | 团队协作、并行会话、横向扩展 |

单 Pod 模式创建恰好一个 Pod，适合个人使用。Deployment 模式创建一个 Kubernetes Deployment，副本数可配置（默认 3），支持多个并行助手会话。运行时通过 `./cc-deploy-deployment.sh scale 5` 进行扩缩容。

### 容器设计

三个镜像共享相同的基础设施：

- **基础 OS：** Ubuntu 24.04
- **编译依赖：** `bison`、`flex`、`cmake`、`gcc`、`g++`、`gdb`、`zlib1g-dev`、`libreadline-dev`——为数据库和系统编程预装
- **非 root 用户：** 创建 `postgres` 用户，UID/GID 与宿主机一致（通过构建参数传入），确保 `hostPath` 卷权限正确
- **共享工作空间：** 容器内 `~/work` 映射到宿主机的 `k8s-work/`，让助手访问源代码

UID/GID 匹配至关重要。Docker 容器通常以 root 或固定 UID 用户运行，但 `hostPath` 挂载保留宿主机的文件系统权限。`build.sh` 脚本自动检测当前用户的 UID 和 GID，并通过 `--build-arg` 传入，使容器内的 `postgres` 用户拥有与构建镜像的宿主机用户完全相同的权限。换一台机器克隆仓库？重新构建即可。

## 模型适配：核心技术难题

项目中技术含量最高的部分是每个助手如何连接智谱 GLM。三个工具使用截然不同的 API 协议，而 GLM 支持不同的子集。下面逐一分析每个鸿沟如何被弥合。

### Claude Code：零修改 API 兼容

Claude Code 原生使用 Anthropic API 协议。智谱 GLM 提供了 Anthropic 兼容端点：

```
https://open.bigmodel.cn/api/anthropic
```

适配只需要 Dockerfile 中的一行：

```dockerfile
ENV ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
```

Claude Code 支持三个模型槽位——Sonnet、Opus 和 Haiku——每个通常映射到不同的 Anthropic 模型。在 aicoding-k8s 中，三个槽位默认都指向 `glm-5.2`，但可以独立覆盖：

```bash
CC_SONNET_MODEL=glm-5.2
CC_OPUS_MODEL=glm-5.2
CC_HAIKU_MODEL=glm-5.2
```

这之所以能工作，是因为智谱的 Anthropic 兼容层忠实地实现了完整的 Anthropic API 接口——流式响应、工具调用、多轮对话。Claude Code 完全感知不到自己在使用非 Anthropic 模型。

Claude Code 的对话历史和设置通过 `hostPath` 挂载持久化：宿主机的 `cc-cache/claude/` 目录映射到容器内的 `~/.claude`，确保数据在 Pod 重启后不丢失。

### OpenCode：容器内配置

OpenCode 采用了不同的方式。它不需要在部署时传入 API Key，配置完全在容器内管理。用户进入容器，运行 `opencode`，以交互方式配置模型提供商。

为确保配置在 Pod 重启后存活，四个目录通过 `hostPath` 挂载：

| 宿主机路径 | 容器路径 | 用途 |
|-----------|---------|------|
| `oc-cache/config` | `~/.config/opencode` | 配置文件 |
| `oc-cache/state` | `~/.local/state/opencode` | 运行状态 |
| `oc-cache/share` | `~/.local/share/opencode` | 共享数据 |
| `oc-cache/cache` | `~/.cache/opencode` | 缓存 |

这些通过 OpenCode 的环境变量（`OC_CONFIG_HOME`、`OC_STATE_HOME` 等）设置，每个映射到宿主机 `oc-cache/` 目录的 `subPath` 挂载。一旦配置完成，设置在 Pod 删除和重建后依然保留。

### Codex CLI：cc-switch 代理协议转换

这是最复杂的适配场景。Codex CLI **仅支持 OpenAI Responses API**（`POST /v1/responses`）。而智谱 GLM **仅支持 Chat Completions API**（`POST /v1/chat/completions`）。这是两个完全不同的协议：

```
OpenAI Responses API:   { input, instructions, tools, ... }
Chat Completions API:   { messages, model, temperature, ... }
```

项目通过 **cc-switch** 解决这个问题——一个跨平台桌面应用（[farion1231/cc-switch](https://github.com/farion1231/cc-switch)），运行在 macOS 宿主机上。cc-switch 内置的代理拦截 Codex CLI 的 Responses API 请求，将其转换为 Chat Completions 格式转发给智谱 GLM：

```
┌──────────────────────────────────────────────────────────┐
│  macOS 宿主机 (OrbStack / Docker Desktop)                  │
│                                                           │
│  ┌───────────────┐     ┌──────────────────────┐          │
│  │   cc-switch   │     │  K8s Pod              │          │
│  │   (桌面应用)   │     │  ┌──────────────┐    │          │
│  │   proxy:15721 │◄────┼──│  Codex CLI   │    │          │
│  │      │        │     │  │              │    │          │
│  │      ▼        │     │  │  config.toml │    │          │
│  │   GLM API     │     │  │  base_url=   │    │          │
│  │               │     │  │  host.docker.│    │          │
│  │               │     │  │  internal    │    │          │
│  └───────────────┘     │  └──────────────┘    │          │
│                        └──────────────────────┘          │
└──────────────────────────────────────────────────────────┘
```

**工作流程（逐步）：**

1. 部署脚本生成 `~/.codex/config.toml`，将 Codex CLI 指向 `http://host.docker.internal:15721/v1`（宿主机上的 cc-switch 代理）
2. Codex CLI 向 cc-switch 代理发送 Responses API 请求
3. cc-switch 将请求从 Responses 格式转换为 Chat Completions 格式
4. cc-switch 将转换后的请求转发到智谱 GLM 的 API
5. 智谱 GLM 返回 Chat Completions 格式的响应
6. cc-switch 将响应反向转换为 Responses 格式，返回给 Codex CLI

**相比 Sidecar 方案的关键优势：** Pod 中没有额外容器——cc-switch 运行在宿主机上，处理所有协议转换。Pod 仅包含 Codex CLI 容器。此外，cc-switch 管理 GLM API Key，因此部署脚本无需传入 API Key。

**自动生成的配置。** 部署脚本在每次 `apply` 时创建 `config.toml`，预配置了三个模型 Profile：

```toml
model = "GLM-5.1"
model_provider = "cc-switch"

[model_providers.cc-switch]
name = "CC Switch Proxy"
base_url = "http://host.docker.internal:15721/v1"
env_key = "CODEX_API_KEY"

[profiles.glm-5-1]
model = "GLM-5.1"
model_provider = "cc-switch"

[profiles.glm-4-6]
model = "glm-4.6"
model_provider = "cc-switch"

[profiles.glm-4-5]
model = "glm-4.5"
model_provider = "cc-switch"
```

在容器内，切换模型无需重新部署：

```bash
codex --config profile=glm-4-6   # 使用 glm-4.6
codex --config profile=glm-4-5   # 使用 glm-4.5
codex --config profile=glm-5-1   # 回到默认 GLM-5.1
```

**前置条件：** cc-switch 必须在宿主机上运行，代理模式已开启（端口 15721），GLM 提供商已配置。参见 [cc-switch 文档](https://github.com/farion1231/cc-switch) 了解设置方法。

## 快速开始

### 前置条件

- Docker、kubectl 和 git（macOS 或 Linux）
- [智谱 API Key](https://open.bigmodel.cn)（Claude Code 和 Codex CLI 需要）
- `envsubst`——Linux 通常预装；macOS 用户：`brew install gettext`

### 第一步：克隆仓库

```bash
git clone https://github.com/davidjiang0618/aicoding-k8s.git
cd aicoding-k8s
```

### 第二步：构建镜像

每个工具有独立的 Docker 镜像，在 `docker/<tool>/` 目录下构建：

```bash
# OpenCode — 先下载二进制文件，再构建
cd docker/oc
./download.sh       # 自动检测架构和最新 GitHub Release 版本
./build.sh          # 构建镜像 oc-dev:1.0.1

# Claude Code — 直接构建（Dockerfile 中 npm install）
cd docker/cc
./build.sh          # 构建镜像 cc-dev:2.0.1

# Codex CLI — 直接构建（Dockerfile 中 npm install）
cd docker/codex_cc
./build.sh          # 构建镜像 codex_cc-dev:1.0.1
```

在任何 `build.sh` 后追加 `clean` 可进行无缓存重建。构建脚本自动检测宿主机 UID/GID——无需手动配置。

> **国内用户提示：** `download.sh` 从 GitHub Releases 下载 OpenCode 二进制文件，可能较慢。请先启动本地代理软件（如 Clash/V2Ray，默认端口 `7890`），再执行：`https_proxy=http://127.0.0.1:7890 ./download.sh`

### 第三步：设置 API Key

```bash
# Claude Code
export ANTHROPIC_AUTH_TOKEN=your-zhipu-api-key

# Codex CLI — 无需 API Key！
# 宿主机上的 cc-switch 管理 GLM 认证。
# 只需确保 cc-switch 已运行，代理模式已开启，GLM 已配置。

# OpenCode 部署时无需 API Key
```

### 第四步：部署

每个工具有专用的部署脚本。脚本创建 `ai` 命名空间、建立缓存目录、解析 YAML 模板中的变量，并提交到 Kubernetes：

```bash
# 单 Pod 模式
./cc-deploy.sh apply

# Deployment 模式（默认 3 副本）
./cc-deploy-deployment.sh apply

# 自定义副本数
CC_REPLICAS=5 ./cc-deploy-deployment.sh apply

# 运行时扩缩容
./cc-deploy-deployment.sh scale 2

# Codex CLI — 无需 API Key（cc-switch 处理认证）
./codex_cc-deploy.sh apply
```

> **重要：** 不要直接运行 `kubectl apply -f cc-pod.yaml`。YAML 文件中包含 `${VAR}` 占位符，需要通过部署脚本的 `envsubst` 解析。

### 第五步：进入容器

```bash
# 查看运行中的 Pod
kubectl get pods -n ai

# 进入单 Pod
kubectl exec -it cc-dev -n ai -- bash

# 进入 Deployment Pod（先从列表中选择）
kubectl exec -it cc-dev-deployment-xxxxx -n ai -- bash
```

工作目录是 `~/work`，映射到宿主机的 `k8s-work/`。文件在宿主机和容器之间实时同步。三个工具共享此工作空间——使用独立的 Git 仓库或子目录来避免冲突。

## 部署脚本的内部设计

所有部署脚本遵循统一的模式，以 `envsubst` 为核心——这是一个用于在文本中替换环境变量的 GNU 工具：

```bash
#!/bin/bash
# 1. 确定项目根目录
export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}

# 2. 设置工具特定的环境变量（带默认值）
export CC_SONNET_MODEL=${CC_SONNET_MODEL:-glm-5.1}
export CC_OPUS_MODEL=${CC_OPUS_MODEL:-glm-5.1}
export CC_HAIKU_MODEL=${CC_HAIKU_MODEL:-glm-5.1}

# 3. 解析 YAML 模板中的所有 ${VAR} 占位符
YAML=$(envsubst < cc-pod.yaml)

# 4. 通过 stdin 将解析后的 YAML 提交给 kubectl
echo "$YAML" | kubectl apply -f -
```

此设计有几个刻意为之的特性：

**YAML 模板不是最终产物。** 模板文件包含 `${ANTHROPIC_AUTH_TOKEN}`、`${AI_K8S_HOME}` 等占位符，只在运行时存在。这防止了使用未解析变量的意外部署，并将密钥排除在版本控制的 YAML 文件之外。

**Stdin 管道而非文件写入。** 解析后的 YAML 通过 stdin 直接管道传给 `kubectl apply`，而非写入中间文件。这避免了在宿主机文件系统上留下明文 API Key。（注意：Kubernetes API Server 确实会将 Pod Spec 存储在 etcd 中；生产环境建议使用开启静态加密的 Kubernetes Secrets。）

**可覆盖的项目根目录。** `AI_K8S_HOME` 默认指向脚本所在目录，但可以通过环境变量覆盖，支持非标准安装路径。

**自动创建依赖。** `apply` 命令在提交 Pod Spec 之前，幂等地创建 `ai` 命名空间和所有必需的缓存目录。无需手动准备。

**子命令模式。** 所有脚本暴露 `apply`、`delete` 和 `status` 子命令。Deployment 脚本额外提供 `scale N`。这种一致性降低了在工具之间切换时的认知负担。

## 总结

aicoding-k8s 解决了 AI 编码助手从个人实验走向团队级部署时所面临的实际基础设施挑战：

1. **安全隔离**通过 Kubernetes Pod 边界实现——每个助手运行在独立的容器中，拥有独立的文件系统，保护主机并支持多助手并发。

2. **无缝模型适配**通过协议兼容实现——Claude Code 使用智谱的 Anthropic 兼容端点，零代码修改；Codex CLI 通过宿主机上的 cc-switch 代理实时转换 Responses 到 Chat Completions。

3. **运维简便**通过 Shell 脚本驱动的部署实现——构建、配置、部署和扩缩容，全部使用熟悉的命令。没有复杂的抽象，没有额外的控制器。

项目开源在 GitHub：https://github.com/davidjiang0618/aicoding-k8s ，欢迎 Star 和贡献。
