#!/bin/bash

# Deploy the codex-dev Deployment (with CCX sidecar) to Kubernetes
# Substitutes ${AI_K8S_HOME}, ${CODEX_API_KEY}, ${CODEX_REPLICAS}, ${CODEX_MODEL}
# and generates ~/.codex/config.toml pointing to CCX proxy for protocol translation
#
# Architecture: Codex CLI → CCX (localhost:3000) → Responses→Chat → Zhipu GLM
#
# Usage:
#   ./codex-deploy-deployment.sh apply       Create/update the deployment (also generates config.toml)
#   ./codex-deploy-deployment.sh delete      Remove the deployment
#   ./codex-deploy-deployment.sh status      Show deployment and pod status
#   ./codex-deploy-deployment.sh scale N     Scale to N replicas
#
# Required:
#   CODEX_API_KEY must be set before running.
#
# Examples:
#   export CODEX_API_KEY=your-glm-api-key && ./codex-deploy-deployment.sh apply
#   CODEX_API_KEY=xxx ./codex-deploy-deployment.sh apply
#
# Override defaults:
#   CODEX_REPLICAS=5 ./codex-deploy-deployment.sh apply
#   CODEX_MODEL=GLM-4.7-FlashX ./codex-deploy-deployment.sh apply
#   AI_K8S_HOME=/your/local/path ./codex-deploy-deployment.sh apply
#
# First-time CCX setup (after apply):
#   kubectl port-forward deployment/codex-dev-deployment 3000:3000 -n ai
#   Open http://localhost:3000 → Add Responses channel → Zhipu GLM
#
# Switch model at runtime inside container:
#   codex --config profile=glm-5-turbo
#   codex --config profile=glm-4-7-flashx
#
# Defaults:
#   AI_K8S_HOME       = directory where this script lives
#   CODEX_REPLICAS    = 3
#   CODEX_MODEL       = GLM-5.1
#
# Available profiles: glm-5-1 (GLM-5.1), glm-5-turbo (GLM-5-Turbo), glm-4-7-flashx (GLM-4.7-FlashX)

export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}
export CODEX_API_KEY=${CODEX_API_KEY:?"ERROR: CODEX_API_KEY is required. Set your GLM API key: export CODEX_API_KEY=your-key"}
export CODEX_REPLICAS=${CODEX_REPLICAS:-3}
export CODEX_MODEL=${CODEX_MODEL:-GLM-5.1}

case "$1" in
  apply)
    kubectl create namespace ai 2>/dev/null || true
    mkdir -p "${AI_K8S_HOME}/codex-cache/codex" "${AI_K8S_HOME}/codex-cache/ccx" "${AI_K8S_HOME}/k8s-work"
    cat > "${AI_K8S_HOME}/codex-cache/codex/config.toml" <<EOF
model = "${CODEX_MODEL}"
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
EOF
    YAML=$(envsubst < codex-deployment.yaml)
    echo "$YAML" | kubectl apply -f -
    ;;
  delete)
    YAML=$(envsubst < codex-deployment.yaml)
    echo "$YAML" | kubectl delete -f -
    ;;
  status)
    kubectl get deployment codex-dev-deployment -n ai
    echo ""
    kubectl get pods -l app=codex-dev -n ai
    ;;
  scale)
    if [ -z "$2" ]; then
      echo "Usage: $0 scale <replica-count>"
      exit 1
    fi
    kubectl scale deployment codex-dev-deployment -n ai --replicas=$2
    echo "Scaled to $2 replicas"
    ;;
  *)
    echo "Usage: $0 {apply|delete|status|scale <N>}"
    exit 1
    ;;
esac
