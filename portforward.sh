#!/usr/bin/env bash
# One-shot: (re)start the three port-forwards for the SRE lab.
# app:        http://localhost:8080   (video-origin)
# prometheus: http://localhost:9090
# grafana:    http://localhost:3000   (admin / sre-lab)
set -e
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 1
nohup kubectl port-forward svc/video-origin 8080:80 >/tmp/pf-app.log 2>&1 &
nohup kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 >/tmp/pf-prom.log 2>&1 &
nohup kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 >/tmp/pf-graf.log 2>&1 &
sleep 3
echo "app:        $(curl -s -o /dev/null -w '%{http_code}' localhost:8080/actuator/health)"
echo "prometheus: $(curl -s -o /dev/null -w '%{http_code}' localhost:9090/-/ready)"
echo "grafana:    $(curl -s -o /dev/null -w '%{http_code}' localhost:3000/api/health)"
