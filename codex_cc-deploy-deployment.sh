#!/bin/bash

# Deploy the codex-cc-dev Deployment (Codex CLI via cc-switch proxy on host) to Kubernetes
# Substitutes ${AI_K8S_HOME}, ${CODEX_API_KEY}, ${CODEX_CC_REPLICAS}, ${CODEX_MODEL}
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
#   ./codex_cc-deploy-deployment.sh apply       Create/update the deployment (also generates config.toml)
#   ./codex_cc-deploy-deployment.sh delete      Remove the deployment
#   ./codex_cc-deploy-deployment.sh status      Show deployment and pod status
#   ./codex_cc-deploy-deployment.sh scale N     Scale to N replicas
#
# Override defaults:
#   CODEX_CC_REPLICAS=5 ./codex_cc-deploy-deployment.sh apply
#   CODEX_MODEL=glm-4.6 ./codex_cc-deploy-deployment.sh apply
#   CC_SWITCH_PORT=15721 ./codex_cc-deploy-deployment.sh apply
#   AI_K8S_HOME=/your/local/path ./codex_cc-deploy-deployment.sh apply
#
# Switch model at runtime inside container:
#   codex --config profile=glm-4-6
#   codex --config profile=glm-4-5
#
# Defaults:
#   AI_K8S_HOME         = directory where this script lives
#   CODEX_CC_REPLICAS   = 3
#   CODEX_MODEL         = GLM-5.1
#   CC_SWITCH_PORT      = 15721
#
# Available profiles: glm-5-1 (GLM-5.1), glm-4-6 (glm-4.6), glm-4-5 (glm-4.5)

export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}
export CODEX_API_KEY=${CODEX_API_KEY:-cc-switch-managed}
export CODEX_CC_REPLICAS=${CODEX_CC_REPLICAS:-3}
export CODEX_MODEL=${CODEX_MODEL:-GLM-5.1}
export CC_SWITCH_PORT=${CC_SWITCH_PORT:-15721}

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
    YAML=$(envsubst < codex_cc-deployment.yaml)
    echo "$YAML" | kubectl apply -f -
    SVC_YAML=$(envsubst < codex_cc-service.yaml)
    echo "$SVC_YAML" | kubectl apply -f -
    ;;
  delete)
    SVC_YAML=$(envsubst < codex_cc-service.yaml)
    echo "$SVC_YAML" | kubectl delete -f - 2>/dev/null || true
    YAML=$(envsubst < codex_cc-deployment.yaml)
    echo "$YAML" | kubectl delete -f -
    ;;
  status)
    kubectl get deployment codex-cc-dev-deployment -n ai
    echo ""
    kubectl get pods -l app=codex-cc-dev -n ai
    ;;
  scale)
    if [ -z "$2" ]; then
      echo "Usage: $0 scale <replica-count>"
      exit 1
    fi
    kubectl scale deployment codex-cc-dev-deployment -n ai --replicas=$2
    echo "Scaled to $2 replicas"
    ;;
  *)
    echo "Usage: $0 {apply|delete|status|scale <N>}"
    exit 1
    ;;
esac
