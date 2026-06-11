# Runbook — video-origin

On-call quick reference. Goal order: **confirm impact → stop the bleeding → then root-cause.**

## First 60 seconds (any alert)
```bash
kubectl get pods -l app=video-origin            # restarts? not ready?
kubectl rollout history deployment/video-origin # was there a recent deploy?
# dashboard: Grafana → "Video Origin — SRE Golden Signals"
```

## 5xx spike  <a id="5xx-spike"></a>
**Alert:** VideoOriginHigh5xxRatio
1. Check rollout history — recent deploy is the prime suspect.
2. If yes → **rollback first, investigate later**:
   ```bash
   kubectl rollout undo deployment/video-origin
   kubectl rollout status deployment/video-origin
   ```
3. Verify recovery: 5xx panel back to ~0; or
   `sum(rate(http_server_requests_seconds_count{job="video-origin",status=~"5.."}[1m]))`
4. No recent deploy? Check downstream deps, config changes, logs:
   `kubectl logs deploy/video-origin --tail=100 | grep -i error`
5. Write the postmortem (template: incidents/postmortem-01).

## Latency (p95 > SLO)  <a id="latency"></a>
**Alert:** VideoOriginP95LatencyHigh
1. Dashboard: is it all endpoints (resource pressure) or one endpoint (code path)?
2. CPU throttling? `kubectl top pods` — near the CPU limit → scale or raise limits:
   `kubectl scale deployment/video-origin --replicas=3`
3. Single endpoint → check recent changes to it; consider rate-limiting or degrading it.

## OOMKilled / restarts  <a id="oomkilled"></a>
**Alerts:** VideoOriginContainerRestarts, VideoOriginMemoryNearLimit
1. Confirm the kill:
   ```bash
   kubectl describe pod -l app=video-origin | grep -A6 "Last State"
   # Reason: OOMKilled, Exit Code: 137 = kernel cgroup kill
   ```
2. **Nothing useful in app logs — this is a container-level kill.**
3. Leading indicator: "memory working set vs limit" panel crossing 90%.
4. Mitigate: raise the limit (leave ≥25-30% headroom over JVM heap target) or fix the leak:
   ```bash
   kubectl patch deployment video-origin --type=json -p='[
     {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"512Mi"}]'
   ```
5. JVM-in-container sizing rule: heap = MaxRAMPercentage(75%) × cgroup limit;
   metaspace + threads + native need the rest. Limit too tight → 137 loop.

## Useful one-liners
```bash
kubectl logs <pod> --previous          # last words of the dead container
kubectl get events --sort-by=.metadata.creationTimestamp | tail
kubectl rollout undo deployment/video-origin --to-revision=<n>
~/sre-lab/portforward.sh               # restore local tunnels (app/prom/grafana)
```
