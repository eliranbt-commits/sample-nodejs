#!/usr/bin/env bash
# Install ArgoCD on the local kind cluster and point it at this repo.
# Requires: kubectl, helm, and (for a private Docker Hub pull) DOCKERHUB_USERNAME + DOCKERHUB_TOKEN.
set -euo pipefail

CLUSTER_CONTEXT="${CLUSTER_CONTEXT:-kind-play}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
APP_NS="${APP_NS:-sample-nodejs}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kubectl config use-context "$CLUSTER_CONTEXT"

kubectl create namespace "$ARGOCD_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$APP_NS" --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${DOCKERHUB_USERNAME:-}" && -n "${DOCKERHUB_TOKEN:-}" ]]; then
  kubectl create secret docker-registry dockerhub \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username="$DOCKERHUB_USERNAME" \
    --docker-password="$DOCKERHUB_TOKEN" \
    --namespace="$APP_NS" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "Skipping dockerhub pull secret (set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN to create it)."
fi

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGOCD_NS" \
  --set server.service.type=ClusterIP \
  --wait \
  --timeout 5m

kubectl apply -f "$ROOT/argocd/application.yaml"

echo
echo "ArgoCD installed. UI:"
echo "  kubectl -n $ARGOCD_NS port-forward svc/argocd-server 8081:80"
echo "  kubectl -n $ARGOCD_NS get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo
echo "App:"
echo "  kubectl -n $APP_NS get pods,svc,ingress"
