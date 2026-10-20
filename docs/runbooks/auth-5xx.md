# Runbook — auth-service high 5xx rate

**Alert:** `AuthServiceHigh5xxRate`
**Trigger:** HTTP 5xx responses > 5% of auth-service traffic over 5 minutes.
**Severity:** critical (pages on-call via PagerDuty, notifies Discord `#incidents`).

## What it means

`auth-service` is the authentication authority — `flag-service` and
`targeting-service` call its `/validate` endpoint on every request, and
`evaluation-service` depends on them. Sustained 5xx from auth-service degrades
the whole platform, so this alert is treated as critical.

## Automated response (self-healing)

When the alert fires, the chain runs automatically:

1. Alertmanager POSTs the alert to the in-cluster **webhook-adapter**.
2. The adapter fires a GitHub `repository_dispatch` (`self-heal`).
3. The **self-heal.yml** GitHub Action runs
   `kubectl rollout restart deployment/auth-service` and waits for rollout.

A rollout restart clears transient faults (stuck DB connections, bad in-memory
state, a wedged pod). If the alert resolves after the restart, no human action
is needed.

## Manual investigation (if self-healing doesn't resolve it)

1. **Check pods**
   ```bash
   kubectl -n auth-service get pods
   kubectl -n auth-service logs deploy/auth-service --tail=100
   ```
2. **Check the database** — auth-service talks to RDS PostgreSQL. 5xx often
   means the DB is unreachable or out of connections.
   ```bash
   kubectl -n auth-service describe deploy/auth-service   # env: DB_HOST, etc.
   ```
   Verify the RDS instance is available and the security group allows the EKS
   node SG.
3. **Check traces in Datadog** — open the APM service map, click `auth-service`,
   and inspect error spans to see whether failures are at the DB layer or in the
   handler.
4. **Check recent deploys** — a bad image from CI could be the cause. Roll back:
   ```bash
   kubectl -n auth-service rollout undo deployment/auth-service
   ```

## Manually trigger self-healing (demo / recovery)

- GitHub → Actions → **Self-Healing — rollout restart** → *Run workflow*
  (input `service=auth-service`), or
- `kubectl -n auth-service rollout restart deployment/auth-service`
