#!/usr/bin/env bash
# Cloud deploy: run ON the server (Ubuntu + k3s + docker installed, repo at /opt/sre-lab)
set -euo pipefail
cd /opt/sre-lab
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== 1/5 build image ==="
docker build -t video-origin:v1 video-origin/
docker save video-origin:v1 | k3s ctr images import -

echo "=== 2/5 app + servicemonitor + alerts + ingress + synthetic traffic ==="
kubectl apply -f k8s/video-origin.yaml -f k8s/servicemonitor.yaml -f k8s/cloud-ingress.yaml

echo "=== 3/5 helm ==="
command -v helm >/dev/null || curl -sf https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "=== 4/5 monitoring stack (4GB-tuned) ==="
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f infra/cloud/values-monitoring.yaml --wait --timeout 12m
kubectl apply -f k8s/alert-rules.yaml

echo "=== 5/5 dashboard ==="
sleep 5
kubectl -n monitoring wait --for=condition=ready pod -l app.kubernetes.io/name=grafana --timeout=180s
curl -s -u admin:sre-lab -H "Content-Type: application/json" \
  -X POST http://grafana.167-233-93-35.nip.io/api/dashboards/db -d @k8s/grafana-dashboard.json | head -c 200; echo

echo "DONE:"
echo "  API:     http://api.167-233-93-35.nip.io/api/videos"
echo "  Grafana: http://grafana.167-233-93-35.nip.io/d/video-origin-sre  (anonymous read-only)"
