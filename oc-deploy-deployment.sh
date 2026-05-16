#!/bin/bash

# Deploy the oc-dev Deployment to Kubernetes
# Substitutes ${AI_K8S_HOME} and ${OC_REPLICAS} in oc-deployment.yaml before applying
#
# Usage:
#   ./oc-deploy-deployment.sh apply       Create/update the deployment
#   ./oc-deploy-deployment.sh delete      Remove the deployment
#   ./oc-deploy-deployment.sh status      Show deployment and pod status
#   ./oc-deploy-deployment.sh scale N     Scale to N replicas
#
# Examples:
#   ./oc-deploy-deployment.sh apply
#   OC_REPLICAS=5 ./oc-deploy-deployment.sh apply
#   AI_K8S_HOME=/your/local/path ./oc-deploy-deployment.sh apply
#
# Defaults:
#   AI_K8S_HOME = directory where this script lives
#   OC_REPLICAS = 3

export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}
export OC_REPLICAS=${OC_REPLICAS:-3}

case "$1" in
  apply)
    kubectl create namespace ai 2>/dev/null || true
    mkdir -p "${AI_K8S_HOME}"/oc-cache/{config,state,share,cache} "${AI_K8S_HOME}/k8s-work"
    YAML=$(envsubst < oc-deployment.yaml)
    echo "$YAML" | kubectl apply -f -
    ;;
  delete)
    YAML=$(envsubst < oc-deployment.yaml)
    echo "$YAML" | kubectl delete -f -
    ;;
  status)
    kubectl get deployment oc-dev-deployment -n ai
    echo ""
    kubectl get pods -l app=oc-dev -n ai
    ;;
  scale)
    if [ -z "$2" ]; then
      echo "Usage: $0 scale <replica-count>"
      exit 1
    fi
    kubectl scale deployment oc-dev-deployment -n ai --replicas=$2
    echo "Scaled to $2 replicas"
    ;;
  *)
    echo "Usage: $0 {apply|delete|status|scale <N>}"
    exit 1
    ;;
esac
