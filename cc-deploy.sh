#!/bin/bash

# Deploy the cc-dev pod to Kubernetes
# Substitutes ${AI_K8S_HOME}, ${ANTHROPIC_AUTH_TOKEN}, and model vars in cc-pod.yaml
#
# Usage:
#   ./cc-deploy.sh apply     Create/update the pod
#   ./cc-deploy.sh delete    Remove the pod
#   ./cc-deploy.sh status    Show pod status
#
# Required:
#   ANTHROPIC_AUTH_TOKEN must be set before running.
#
# Examples:
#   export ANTHROPIC_AUTH_TOKEN=your-glm-api-key && ./cc-deploy.sh apply
#   ANTHROPIC_AUTH_TOKEN=xxx ./cc-deploy.sh apply
#
# Override defaults:
#   CC_SONNET_MODEL=GLM-4.7-FlashX ./cc-deploy.sh apply
#   AI_K8S_HOME=/your/local/path ./cc-deploy.sh apply
#
# Defaults:
#   AI_K8S_HOME       = directory where this script lives
#   CC_SONNET_MODEL   = glm-5.1
#   CC_OPUS_MODEL     = glm-5.1
#   CC_HAIKU_MODEL    = glm-5.1

export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}
export ANTHROPIC_AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN:?"ERROR: ANTHROPIC_AUTH_TOKEN is required. Set your GLM API key: export ANTHROPIC_AUTH_TOKEN=your-key"}
export CC_SONNET_MODEL=${CC_SONNET_MODEL:-glm-5.2}
export CC_OPUS_MODEL=${CC_OPUS_MODEL:-glm-5.2}
export CC_HAIKU_MODEL=${CC_HAIKU_MODEL:-glm-5.2}

YAML=$(envsubst < cc-pod.yaml)

case "$1" in
  apply)
    kubectl create namespace ai 2>/dev/null || true
    mkdir -p "${AI_K8S_HOME}/cc-cache/claude" "${AI_K8S_HOME}/k8s-work"
    echo "$YAML" | kubectl apply -f -
    ;;
  delete)
    echo "$YAML" | kubectl delete -f -
    ;;
  status)
    kubectl get pod cc-dev -n ai
    ;;
  *)
    echo "Usage: $0 {apply|delete|status}"
    exit 1
    ;;
esac
