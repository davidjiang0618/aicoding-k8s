# Dev environment image for building databases (PostgreSQL, Redis, etc.)
# with Claude Code pre-installed for AI-assisted development
# Uses GLM models via Anthropic-compatible API (Zhipu AI)
FROM ubuntu:24.04

# Install build dependencies for database compilation,
# development tools, sudo (for postgres user), Node.js 22+, and CA certs
RUN apt-get update && \
    apt-get install -y \
      bison flex cmake make gcc g++ gdb cgdb \
      zlib1g-dev libreadline-dev zlib1g vim \
      perl curl git sudo ca-certificates && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js 22.x (required by Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user matching host UID/GID for volume mount access
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN set -eux; \
    GROUP_NAME=$(getent group ${GROUP_ID} | cut -d: -f1) || true; \
    if [ -z "$GROUP_NAME" ]; then \
        groupadd -g ${GROUP_ID} postgres; \
        GROUP_NAME=postgres; \
    fi; \
    useradd -u ${USER_ID} -g "$GROUP_NAME" -o -m -s /bin/bash postgres; \
    usermod -aG sudo postgres; \
    echo 'postgres ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/postgres; \
    mkdir -p /home/postgres/.claude \
             /home/postgres/work; \
    chown -R postgres:"$GROUP_NAME" /home/postgres

USER postgres
WORKDIR /home/postgres

# GLM model configuration via Zhipu AI Anthropic-compatible API
# ANTHROPIC_AUTH_TOKEN is injected at deploy time via pod env vars
ENV ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
ENV API_TIMEOUT_MS=3000000
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ENV NODE_TLS_REJECT_UNAUTHORIZED=0

# Keep container running for interactive kubectl exec
CMD ["sleep", "infinity"]
