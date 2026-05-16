# Dev environment image for building databases (PostgreSQL, Redis, etc.)
# with OpenCode pre-installed for AI-assisted development
FROM ubuntu:24.04

# Install build dependencies for database compilation,
# development tools, sudo (for postgres user), and CA certs
RUN apt-get update && \
    apt-get install -y \
      bison flex cmake make gcc g++ gdb cgdb \
      zlib1g-dev libreadline-dev zlib1g vim \
      perl curl git sudo ca-certificates && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Copy pre-downloaded binary (run download.sh first) ---
COPY bin/opencode /usr/local/bin/opencode
RUN chmod +x /usr/local/bin/opencode

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
    mkdir -p /home/postgres/.config/opencode \
             /home/postgres/.local/state/opencode \
             /home/postgres/.local/share/opencode \
             /home/postgres/.cache/opencode \
             /home/postgres/work; \
    chown -R postgres:"$GROUP_NAME" /home/postgres

USER postgres
WORKDIR /home/postgres

# OpenCode directory environment variables
# Each path maps to a subPath mount from the host oc-cache/ directory
ENV OC_CONFIG_HOME=/home/postgres/.config/opencode
ENV OC_STATE_HOME=/home/postgres/.local/state/opencode
ENV OC_SHARE_HOME=/home/postgres/.local/share/opencode
ENV OC_CACHE_HOME=/home/postgres/.cache/opencode

# Disable TLS verification for local development only
ENV NODE_TLS_REJECT_UNAUTHORIZED=0

# Keep container running for interactive kubectl exec
CMD ["sleep", "infinity"]

