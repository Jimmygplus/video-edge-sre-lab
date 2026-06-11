# Postmortem 01 — Bad release causes 5xx spike on /api/videos

**Date:** 2026-06-11 · **Severity:** SEV2 (hot path degraded, ~40% of catalogue requests failing) · **Status:** resolved

## Summary
Release v2 of `video-origin` shipped a regression (failure injection via `FAILURE_RATE=0.4`,
standing in for a real code bug) that returned HTTP 500 on ~40% of `/api/videos` requests.
Detected via the 5xx-ratio panel/PromQL within a minute of full rollout; mitigated by
`kubectl rollout undo`. **MTTR (detection → recovery): 72 seconds.**

## Timeline (AEST)
| Time | Event |
|---|---|
| 11:19:05 | v2 deployment starts (rolling update, maxUnavailable=0) |
| 11:19:37 | v2 fully rolled out; Locust traffic (30 users) hitting it |
| 11:20:35 | **Detection:** 5xx ratio 12.8% and climbing (steady-state would be ~22%) |
| 11:20:54 | **Mitigation decision:** recent deploy = prime suspect → `kubectl rollout undo deployment/video-origin` |
| 11:21:24 | Rollback complete, image back to v1 |
| 11:21:47 | **Recovery confirmed:** 5xx rate on /api/videos back to 0/s |

## Detection
PromQL: `sum(rate(http_server_requests_seconds_count{job="video-origin",status=~"5.."}[2m])) / sum(rate(http_server_requests_seconds_count{job="video-origin"}[2m]))`
Grafana panel: "5xx error ratio" on the Video Origin — SRE Golden Signals dashboard.

## Root cause
v2 introduced an environment-driven failure path on the catalogue endpoint
(`FAILURE_RATE` honoured in `videos()`); deployed with `FAILURE_RATE=0.4`.
In a real-world analogue: a code change that throws on a subset of requests.

## What went well
- Rolling update with `maxUnavailable: 0` meant capacity never dropped during deploy or rollback.
- "Recent change first" heuristic led straight to rollback; root-causing was deferred until after recovery.
- Dashboard + PromQL made detection trivial.

## What went poorly
- No automated alert yet — detection was eyes-on-dashboard. (Action item 1.)
- No canary/staged rollout — 100% of traffic hit the bad version. (Action item 2.)

## Action items
1. Add a PrometheusRule alert: 5xx ratio > 5% for 2m → Alertmanager. **(done — see k8s/alert-rules.yaml)**
2. Consider canary strategy (e.g. Argo Rollouts / weighted services) for future iterations.
3. Add a pre-deploy smoke test hitting /api/videos in CI.
