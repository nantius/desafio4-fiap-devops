# Alerting & Self-Healing — deploy-time secrets

The alert → incident → notification → self-healing chain needs a few secrets
that are **never committed**. Create them before (or just after) ArgoCD syncs
the `alerting` and `otel-collector` apps.

## 1. Alertmanager routing secret (PagerDuty + Discord)

Used by `alertmanager-config.yaml`.

```bash
kubectl -n observability create secret generic alertmanager-toggle-secrets \
  --from-literal=pagerduty-routing-key='<PAGERDUTY_INTEGRATION_KEY>' \
  --from-literal=discord-webhook-url='https://discord.com/api/webhooks/XXX/YYY/slack'
```

Notes:
- **PagerDuty**: in PagerDuty create a service with an *Events API v2* integration
  and copy its **Integration Key** (routing key).
- **Discord**: create a channel webhook, then append `/slack` to the URL so
  Alertmanager's Slack-compatible sender works against it.

## 2. Self-healing GitHub token (webhook-adapter)

Used by `../self-healing/deployment.yaml`. A PAT that can fire
`repository_dispatch` on this repo (classic PAT with `repo` scope, or a
fine-grained token with **Contents: read/write** on
`nantius/desafio4-fiap-devops`).

```bash
kubectl -n observability create secret generic selfheal-github-token \
  --from-literal=token='<GITHUB_PAT>'
```

## 3. Datadog API key (OTel Collector)

Used by `../otel-collector/values.yaml`.

```bash
kubectl -n observability create secret generic datadog-secret \
  --from-literal=api-key='<DATADOG_API_KEY>'
```

## 4. Grafana admin (kube-prometheus-stack)

```bash
kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<STRONG_PASSWORD>'
```

## GitHub repository secrets (for the self-heal Action)

The `self-heal.yml` workflow restarts the deployment via `kubectl`. It needs the
same Lab AWS credentials as the CI pipelines plus the cluster name:

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`
- `EKS_CLUSTER_NAME` (e.g. `toggle`)

## Flow summary

```
auth 5xx > 5%
   └─ Prometheus evaluates PrometheusRule  →  Alertmanager (AlertmanagerConfig)
        ├─ PagerDuty  : opens an incident
        ├─ Discord    : posts a notification to #incidents
        └─ webhook-adapter (in-cluster)
             └─ GitHub repository_dispatch (self-heal)
                  └─ self-heal.yml Action: kubectl rollout restart deployment/auth-service
```
