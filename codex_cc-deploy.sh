#!/bin/bash

# Deploy the codex-cc-dev pod (Codex CLI via cc-switch proxy on host) to Kubernetes
# Substitutes ${AI_K8S_HOME}, ${CODEX_API_KEY}, ${CODEX_MODEL} in codex_cc-pod.yaml
# and generates ~/.codex/config.toml pointing to cc-switch proxy on the host
#
# Architecture: Codex CLI → host.docker.internal:15721 (cc-switch) → Zhipu GLM
#
# Prerequisite: cc-switch desktop app running on host with proxy enabled (port 15721)
#               and GLM provider configured in cc-switch (API key managed by cc-switch)
#
# No API key needed: cc-switch handles upstream GLM authentication.
# CODEX_API_KEY is set to a dummy value (Codex CLI requires the env var to exist).
#
# Usage:
#   ./codex_cc-deploy.sh apply     Create/update the pod (also generates config.toml)
#   ./codex_cc-deploy.sh delete    Remove the pod
#   ./codex_cc-deploy.sh status    Show pod status
#
# Override defaults:
#   CODEX_MODEL=glm-4.6 ./codex_cc-deploy.sh apply
#   CC_SWITCH_PORT=15721 ./codex_cc-deploy.sh apply
#   AI_K8S_HOME=/your/local/path ./codex_cc-deploy.sh apply
#
# Switch model at runtime inside container:
#   codex --config profile=glm-4-6
#   codex --config profile=glm-4-5
#
# Defaults:
#   AI_K8S_HOME       = directory where this script lives
#   CODEX_MODEL       = GLM-5.1
#   CC_SWITCH_PORT    = 15721
#
# Available profiles: glm-5-1 (GLM-5.1), glm-4-6 (glm-4.6), glm-4-5 (glm-4.5)

export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}
export CODEX_API_KEY=${CODEX_API_KEY:-cc-switch-managed}
export CODEX_MODEL=${CODEX_MODEL:-GLM-5.1}
export CC_SWITCH_PORT=${CC_SWITCH_PORT:-15721}

YAML=$(envsubst < codex_cc-pod.yaml)
SVC_YAML=$(envsubst < codex_cc-service.yaml)

case "$1" in
  apply)
    kubectl create namespace ai 2>/dev/null || true
    mkdir -p "${AI_K8S_HOME}/codex_cc-cache/codex" "${AI_K8S_HOME}/k8s-work"
    cat > "${AI_K8S_HOME}/codex_cc-cache/codex/config.toml" <<EOF
model = "${CODEX_MODEL}"
model_provider = "cc-switch"

[model_providers.cc-switch]
name = "CC Switch Proxy"
base_url = "http://host.docker.internal:${CC_SWITCH_PORT}/v1"
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
EOF
    echo "$YAML" | kubectl apply -f -
    echo "$SVC_YAML" | kubectl apply -f -
    ;;
  delete)
    echo "$SVC_YAML" | kubectl delete -f - 2>/dev/null || true
    echo "$YAML" | kubectl delete -f -
    ;;
  status)
    kubectl get pod codex-cc-dev -n ai
    ;;
  *)
    echo "Usage: $0 {apply|delete|status}"
    exit 1
    ;;
esac
