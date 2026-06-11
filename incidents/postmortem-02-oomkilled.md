# Postmortem 02 — OOMKilled after memory-limit misconfiguration

**Date:** 2026-06-11 · **Severity:** SEV3 (single replica restart loop risk; second replica kept serving) · **Status:** resolved

## Summary
Container memory limit was lowered from 512Mi to 320Mi (simulating a capacity
misconfiguration). A heap-retaining workload (`/api/hog`, 40MB blocks) pushed the JVM past
the cgroup limit; the kernel killed the container (**OOMKilled, exit code 137**) and the pod
restarted. Service stayed up because the Deployment ran 2 replicas and the Service only
routes to ready pods.

## Timeline (AEST)
| Time | Event |
|---|---|
| 11:22:51 | Memory request/limit lowered to 256Mi/320Mi; rollout completes |
| 11:23:42 | /api/hog begins retaining 40MB heap blocks |
| 11:23:48 | After 3 blocks (~120MB retained + JVM baseline), kernel kills container |
| 11:23:59 | Pod shows `RESTARTS: 1`, briefly `0/1 Ready` until readiness probe passes |
| 11:24:39 | **Fix:** memory restored to request 384Mi / limit 512Mi |
| 11:25:08 | All pods healthy, restart counter stable |

## Diagnosis evidence
```
kubectl describe pod -l app=video-origin
    Last State:  Terminated
      Reason:    OOMKilled
      Exit Code: 137        # 128 + 9 (SIGKILL from the kernel cgroup OOM killer)
```
Dashboard: "Pod restarts" panel incremented; "Container memory working set vs limit"
shows the working set crossing the limit line.

## Root cause
Limit (320Mi) left insufficient headroom: JVM heap target was 75% of the cgroup
(`-XX:MaxRAMPercentage=75` → ~240Mi) but heap + metaspace + thread stacks + native
overhead exceeded 320Mi once ~120MB of objects were retained.

## Learnings
- **OOMKilled is a container-level kill, not a Java exception** — nothing in the app log;
  the evidence lives in `describe pod` / events / restart metrics.
- Exit code 137 = SIGKILL; for the JVM, size heap from the limit and leave ≥25-30% headroom.
- Two replicas + readiness probes = the failure was invisible to users.

## Action items
1. Alert on container restarts > 0 in 10m and on memory working set > 90% of limit. **(done — k8s/alert-rules.yaml)**
2. Document the JVM-in-containers sizing rule in the runbook.
3. (Future) Add `kubectl top` / VPA recommendations before changing limits.
