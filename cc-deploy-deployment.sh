#!/bin/bash

# Deploy the cc-dev Deployment to Kubernetes
# Substitutes ${AI_K8S_HOME}, ${ANTHROPIC_AUTH_TOKEN}, ${CC_REPLICAS} and model vars
#
# Usage:
#   ./cc-deploy-deployment.sh apply       Create/update the deployment
#   ./cc-deploy-deployment.sh delete      Remove the deployment
#   ./cc-deploy-deployment.sh status      Show deployment and pod status
#   ./cc-deploy-deployment.sh scale N     Scale to N replicas
#
# Required:
#   ANTHROPIC_AUTH_TOKEN must be set before running.
#
# Examples:
#   export ANTHROPIC_AUTH_TOKEN=your-glm-api-key && ./cc-deploy-deployment.sh apply
#   ANTHROPIC_AUTH_TOKEN=xxx ./cc-deploy-deployment.sh apply
#
# Override defaults:
#   CC_REPLICAS=5 ./cc-deploy-deployment.sh apply
#   CC_SONNET_MODEL=GLM-4.7-FlashX ./cc-deploy-deployment.sh apply
#   AI_K8S_HOME=/your/local/path ./cc-deploy-deployment.sh apply
#
# Defaults:
#   AI_K8S_HOME       = directory where this script lives
#   CC_REPLICAS       = 3
#   CC_SONNET_MODEL   = glm-5.1
#   CC_OPUS_MODEL     = glm-5.1
#   CC_HAIKU_MODEL    = glm-5.1

export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}
export ANTHROPIC_AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN:?"ERROR: ANTHROPIC_AUTH_TOKEN is required. Set your GLM API key: export ANTHROPIC_AUTH_TOKEN=your-key"}
export CC_REPLICAS=${CC_REPLICAS:-3}
export CC_SONNET_MODEL=${CC_SONNET_MODEL:-glm-5.1}
export CC_OPUS_MODEL=${CC_OPUS_MODEL:-glm-5.1}
export CC_HAIKU_MODEL=${CC_HAIKU_MODEL:-glm-5.1}

case "$1" in
  apply)
    kubectl create namespace ai 2>/dev/null || true
    mkdir -p "${AI_K8S_HOME}/cc-cache/claude" "${AI_K8S_HOME}/k8s-work"
    YAML=$(envsubst < cc-deployment.yaml)
    echo "$YAML" | kubectl apply -f -
    ;;
  delete)
    YAML=$(envsubst < cc-deployment.yaml)
    echo "$YAML" | kubectl delete -f -
    ;;
  status)
    kubectl get deployment cc-dev-deployment -n ai
    echo ""
    kubectl get pods -l app=cc-dev -n ai
    ;;
  scale)
    if [ -z "$2" ]; then
      echo "Usage: $0 scale <replica-count>"
      exit 1
    fi
    kubectl scale deployment cc-dev-deployment -n ai --replicas=$2
    echo "Scaled to $2 replicas"
    ;;
  *)
    echo "Usage: $0 {apply|delete|status|scale <N>}"
    exit 1
    ;;
esac
