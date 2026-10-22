# Live-window runbook — apply, demo, destroy

Goal: keep the AWS infra online for the **minimum** time. Everything below is
ordered so you can move fast. Estimated cluster uptime: ~45–90 min including the
video.

> Prereqs gathered ahead of time: Datadog API key, Discord webhook URL
> (with `/slack`), PagerDuty Events API v2 integration key, GitHub PAT.
> Pick a Grafana admin password when you get there.

---

## 0. Refresh Lab credentials (they rotate each session)

From the AWS Academy portal → **AWS Details** → copy the CLI block into
`~/.aws/credentials` (profile `[default]`). Then verify:

```bash
aws sts get-caller-identity --region us-east-1   # expect Account 670047672777
```

---

## 1. Provision infrastructure (Terraform)

```bash
cd terraform
terraform init      # backend already bootstrapped (S3 + DynamoDB)
terraform apply     # ~15-20 min (EKS is the slow part); review plan, type yes
```

Then point kubectl at the new cluster:

```bash
aws eks update-kubeconfig --name toggle --region us-east-1
kubectl get nodes   # confirm nodes are Ready
```

---

## 2. Create the cluster secrets (namespace: observability)

The observability namespace is created by ArgoCD; if it doesn't exist yet:
```bash
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
```

```bash
# Datadog (OTel Collector)
kubectl -n observability create secret generic datadog-secret \
  --from-literal=api-key='<DATADOG_API_KEY>'

# Grafana admin (pick a password)
kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<CHOOSE_A_PASSWORD>'

# Alertmanager routing: PagerDuty + Discord (note the /slack suffix on Discord)
kubectl -n observability create secret generic alertmanager-toggle-secrets \
  --from-literal=pagerduty-routing-key='<PAGERDUTY_INTEGRATION_KEY>' \
  --from-literal=discord-webhook-url='<DISCORD_WEBHOOK_URL>/slack'

# Self-healing: GitHub PAT for the webhook-adapter
kubectl -n observability create secret generic selfheal-github-token \
  --from-literal=token='<GITHUB_PAT>'
```

---

## 3. GitHub repository secrets (for CI + self-heal Action)

Repo → Settings → Secrets and variables → Actions. Set/refresh:

- `AWS_ACCOUNT_ID` = `670047672777`
- `AWS_REGION` = `us-east-1`
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` = current Lab creds
- `EKS_CLUSTER_NAME` = `toggle`

Also confirm: Settings → Actions → General → Workflow permissions =
**Read and write**.

---

## 4. Build & push images (first time)

The deployments reference ECR images that must exist. Trigger each service
pipeline (push a trivial change, or Actions → Run workflow) so CI builds and
pushes to ECR, including `webhook-adapter`. ArgoCD then syncs the new tags.

Verify ArgoCD is managing everything:
```bash
kubectl -n argocd get applications
# or port-forward the UI:
kubectl -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080  (admin password: see below)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

---

## 5. Capture evidence (the rubric requires these)

1. **ArgoCD** UI showing the 5 services + observability apps Synced/Healthy.
2. **Grafana dashboard** with data:
   ```bash
   kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
   # http://localhost:3000  → dashboard "ToggleMaster — Ecosystem Health"
   ```
3. **Datadog** APM: make a request to `/evaluate`, then show the **distributed
   trace** and the **service map** (5 services connected).
   ```bash
   # example load against the evaluation-service ingress path
   curl "http://<NLB_HOST>/evaluate?user_id=u1&flag_name=test-flag"
   ```
4. **Trigger the incident + self-healing** (the "prova real"):
   - Break auth-service to produce 5xx (simplest: scale its DB job / set a bad
     env, or temporarily point `DB_HOST` to an invalid host and restart it so
     `/validate` returns 5xx).
   - Watch the alert go **Firing** in Prometheus/Alertmanager (or Datadog).
   - Show the **PagerDuty** incident open + the **Discord** notification.
   - Show the **self-heal GitHub Action** run and the auth-service pod
     restarting:
     ```bash
     kubectl -n auth-service get pods -w
     ```

Screenshots to collect: dashboard, distributed trace, service map, alert firing,
PagerDuty incident, Discord message, self-heal Action log + pod restart, ArgoCD.

---

## 6. Record the demo video (≤25 min)

Follow the rubric order: overview (EKS + ArgoCD running) → metrics/logs/OTel in
Grafana → APM traces + service map in Datadog → incident + self-healing live.

---

## 7. TEAR DOWN (stop the cost!)

```bash
cd terraform
terraform destroy   # type yes
```

Double-check nothing lingers (EKS, NAT gateway, RDS, NLB are the pricey ones):
```bash
aws eks list-clusters --region us-east-1
aws ec2 describe-nat-gateways --region us-east-1 \
  --filter Name=state,Values=available
aws rds describe-db-instances --region us-east-1 \
  --query 'DBInstances[].DBInstanceIdentifier'
aws elbv2 describe-load-balancers --region us-east-1 \
  --query 'LoadBalancers[].LoadBalancerName'
```

The S3 state bucket + DynamoDB lock table are intentionally **not** destroyed
(they're in the separate bootstrap state and cost ~nothing).

---

## Fill the report

Update `docs/RELATORIO-FASE4.md`: names/RMs/Discord handles, the video link, and
paste the 8 evidence screenshots. Export to PDF.
