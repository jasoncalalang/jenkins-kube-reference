#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="${NAMESPACE:-jenkins}"
RELEASE="${RELEASE:-jenkins}"
VALUES="${VALUES_FILE:-$DIR/values.yaml}"

echo '==> Applying bootstrap (build namespace + in-cluster registry + RBAC)'
kubectl apply -f "$DIR/bootstrap/00-namespace.yaml"
kubectl apply -f "$DIR/bootstrap/01-registry-pvc.yaml"
kubectl apply -f "$DIR/bootstrap/02-registry.yaml"
kubectl apply -f "$DIR/bootstrap/04-rbac.yaml"

if command -v kind >/dev/null 2>&1; then
  echo '==> kind detected — retrofitting containerd registry mirror'
  bash "$DIR/bootstrap/03-kind-registry-mirror.sh"
fi

echo '==> Adding Helm repo'
helm repo add jenkins https://charts.jenkins.io 2>/dev/null || true
helm repo update jenkins

echo "==> Creating namespace $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Jenkins release $RELEASE"
helm upgrade --install "$RELEASE" jenkins/jenkins --namespace "$NAMESPACE" --values "$VALUES" --wait --timeout 10m

echo '==> Done. Retrieve admin password:'
echo "  kubectl -n $NAMESPACE get secret $RELEASE -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo"
