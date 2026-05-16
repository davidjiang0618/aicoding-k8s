#!/bin/bash

# Deploy the oc-dev pod to Kubernetes
# Substitutes ${AI_K8S_HOME} in oc-pod.yaml before applying
#
# Usage:
#   ./oc-deploy.sh apply     Create/update the pod
#   ./oc-deploy.sh delete    Remove the pod
#   ./oc-deploy.sh status    Show pod status
#
# Examples:
#   ./oc-deploy.sh apply
#   AI_K8S_HOME=/your/local/path ./oc-deploy.sh apply
#
# Defaults:
#   AI_K8S_HOME = directory where this script lives

export AI_K8S_HOME=${AI_K8S_HOME:-$(cd "$(dirname "$0")" && pwd)}
YAML=$(envsubst < oc-pod.yaml)

case "$1" in
  apply)
    kubectl create namespace ai 2>/dev/null || true
    mkdir -p "${AI_K8S_HOME}"/oc-cache/{config,state,share,cache} "${AI_K8S_HOME}/k8s-work"
    echo "$YAML" | kubectl apply -f -
    ;;
  delete)
    echo "$YAML" | kubectl delete -f -
    ;;
  status)
    kubectl get pod oc-dev -n ai
    ;;
  *)
    echo "Usage: $0 {apply|delete|status}"
    exit 1
    ;;
esac
