#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="vibekube-dev"
CONTEXT_NAME="kind-${CLUSTER_NAME}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required."
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required."
  exit 1
fi

if ! command -v kind >/dev/null 2>&1; then
  echo "kind is required. Install it with: brew install kind"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not reachable. Start Docker Desktop, then run this script again."
  exit 1
fi

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT_DIR}/kind-config.yaml"
else
  echo "kind cluster ${CLUSTER_NAME} already exists."
fi

kubectl config use-context "${CONTEXT_NAME}"
kubectl apply -f "${ROOT_DIR}/manifests/demo.yaml"
kubectl -n vibekube-demo rollout status deployment/echo-web --timeout=180s
kubectl -n vibekube-demo rollout status deployment/log-counter --timeout=180s

echo
echo "Vibekube dev cluster is ready."
echo "Context: ${CONTEXT_NAME}"
echo "Namespace: vibekube-demo"
echo "Web demo: http://localhost:18080"
echo
kubectl -n vibekube-demo get pods,svc,deploy,cronjob
