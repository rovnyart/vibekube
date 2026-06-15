#!/usr/bin/env bash
set -euo pipefail

kubectl config use-context kind-vibekube-dev >/dev/null
kubectl cluster-info
echo
kubectl -n vibekube-demo get pods,svc,deploy,cronjob,jobs
