# Postmortem 03 — Cloud host reboot; full stack self-healed in ~2 minutes

**Date:** 2026-06-11 (AEST 2026-06-12) · **Severity:** SEV3 (public surfaces unavailable ~2-3 min) · **Status:** resolved, no manual intervention

## Summary
The Hetzner host rebooted at 23:25:27 (host time). All public surfaces (API via Traefik,
Grafana) went unreachable for the boot window. k3s started via systemd on boot; Kubernetes
reconciled every workload automatically. **API and Grafana returned HTTP 200 within ~2
minutes of boot, with zero manual action.**

## Timeline (host time)
| Time | Event |
|---|---|
| ~23:24 | Symptom observed: dashboard panels "No data", Grafana toast "no available server"; SSH attempt timed out |
| 23:25:27 | Host boots (`uptime -s`) |
| 23:26-27 | k3s up; all pods restart (restart counters +1, traefik/svclb last) |
| 23:27:4x | API 200, Grafana 200, Prometheus scraping 3/3 targets, QPS flowing |

## Detection
Human (viewing the dashboard at the time). No synthetic uptime monitoring existed yet — see action items.

## Root cause
Host power-cycle (no unattended-upgrade reboot entry in logs; consistent with a manual
power toggle from the Hetzner console). Exact trigger unconfirmed.

## What went well
- **Self-healing by design:** k3s systemd unit + Kubernetes reconciliation brought back
  10/10 pods with no human action.
- Diagnosis path was clean: ping OK → SSH OK → port 80 down → all containers restarted
  "52s ago" → `uptime -s` confirmed reboot.

## What went poorly
- No external uptime monitoring → outage observed by luck, duration known only roughly.
- Brief misdiagnosis risk: "No data" panels looked like a dashboard/datasource bug;
  actual cause was the datastore (Prometheus) being down during boot.

## Action items
1. External uptime monitoring (UptimeRobot free) on `/actuator/health` — gives real
   availability numbers and alerting. **(planned, next)**
2. Label console power controls mentally as "production hazard" — prefer `reboot` via SSH
   with a pre-check, or at least know a reboot is expected to self-heal in ~2 min.
3. (Nice-to-have) Boot-time smoke test unit that posts a "stack healthy" line to a log
   after reconciliation completes.
