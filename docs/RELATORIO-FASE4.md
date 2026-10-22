# Tech Challenge — Fase 4
## ToggleMaster: Observabilidade Total e Resposta Ativa

> **Como gerar o PDF:** este arquivo é o rascunho do relatório. Preencha os
> campos `<...>` (nomes, RMs, links, prints) e exporte para PDF (ex.: extensão
> "Markdown PDF" no VS Code, `pandoc RELATORIO-FASE4.md -o relatorio.pdf`, ou
> cole no Google Docs e exporte).

---

## 1. Identificação

| Nome | RM | Usuário Discord |
|------|----|-----------------|
| `<Nome 1>` | `<RM>` | `<@discord>` |
| `<Nome 2>` | `<RM>` | `<@discord>` |
| `<Nome 3>` | `<RM>` | `<@discord>` |

- **Repositório de código:** https://github.com/nantius/desafio4-fiap-devops
- **Vídeo de demonstração:** `<link YouTube / Drive>`

---

## 2. Visão geral

Esta fase adiciona **observabilidade total e resposta ativa** sobre a base
automatizada das Fases 1–3 do ToggleMaster (5 microsserviços, infraestrutura em
Terraform, CI/CD com DevSecOps e GitOps via ArgoCD no EKS).

O que foi construído:

1. **Stack de monitoramento open source** (Prometheus, Loki, Grafana) provisionada
   no cluster via GitOps.
2. **OpenTelemetry Collector** como peça central que recebe toda a telemetria dos
   microsserviços e a roteia para os backends corretos.
3. **Instrumentação** dos 5 microsserviços com OpenTelemetry (traces, métricas e
   logs), incluindo **tracing distribuído** ao longo do caminho de avaliação.
4. **APM** com Datadog (service map + traces distribuídos).
5. **Alertas inteligentes + self-healing**: alerta de taxa de erro 5xx →
   incidente no PagerDuty → notificação no Discord → automação que reinicia o
   serviço afetado.

### Nota sobre o ambiente (AWS Academy / LabRole)

Todo o projeto roda na conta **AWS Academy (Lab)**, que **não permite criar
Roles/Policies de IAM**. A base foi adaptada para:
- reutilizar a **LabRole** existente no cluster EKS e nos node groups;
- remover o módulo IAM e o uso de **IRSA** (os pods herdam a LabRole do nó);
- substituir o **KEDA** (que depende de IRSA) por **HPA baseado em CPU** no
  analytics-service;
- autenticar o CI/CD e o self-healing com as **credenciais temporárias do Lab**.

---

## 3. Arquitetura de Observabilidade (OTel)

### 3.1 Fluxo de telemetria

```
┌──────────────┐   ┌──────────────┐   ┌──────────────────┐   ┌──────────────┐
│ auth-service │   │ flag-service │   │ evaluation-svc   │   │ analytics-svc│
│    (Go)      │   │  (Python)    │   │     (Go)         │   │  (Python)    │
└──────┬───────┘   └──────┬───────┘   └────────┬─────────┘   └──────┬───────┘
       │ OTLP             │ OTLP               │ OTLP               │ OTLP
       └──────────────────┴─────────┬──────────┴────────────────────┘
                                     ▼
                        ┌────────────────────────┐
                        │   OpenTelemetry         │   (peça central obrigatória)
                        │   Collector (gateway)   │
                        └───────────┬─────────────┘
              traces │      metrics │               │ logs
                     ▼              ▼               ▼
            ┌──────────────┐ ┌────────────┐ ┌────────────┐
            │   Datadog    │ │ Prometheus │ │    Loki    │
            │ (APM/traces/ │ │ (métricas) │ │   (logs)   │
            │ service map) │ └─────┬──────┘ └─────┬──────┘
            └──────────────┘       └──────┬───────┘
                                          ▼
                                    ┌───────────┐
                                    │  Grafana  │ (dashboard único)
                                    └───────────┘
```

(targeting-service, também Python, segue o mesmo padrão do flag-service.)

### 3.2 Por que o OTel Collector no centro

Os microsserviços **não** falam diretamente com cada backend. Eles exportam um
único formato (**OTLP**) para o Collector, que faz o roteamento:

- **traces** → Datadog (exporter `datadog`) — habilita APM, service map e tracing
  distribuído;
- **métricas** → Datadog **e** Prometheus (exporter `prometheusremotewrite`);
- **logs** → Loki (exporter `otlphttp/loki`).

Benefícios: um só ponto de configuração, troca de backend sem tocar no código das
aplicações, e enriquecimento central (processor `k8sattributes` adiciona
namespace/pod/deployment a cada telemetria).

Pipelines definidos (ver `manifests/observability/otel-collector/values.yaml`):

| Pipeline | Receivers | Processors | Exporters |
|----------|-----------|------------|-----------|
| traces | otlp | k8sattributes, resourcedetection, batch | datadog |
| metrics | otlp | k8sattributes, resourcedetection, batch | datadog, prometheusremotewrite |
| logs | otlp | k8sattributes, resourcedetection, batch | otlphttp/loki |

### 3.3 Instrumentação dos serviços

- **Go (auth, evaluation):** OpenTelemetry SDK manual (`otel.go`), handler HTTP
  encapsulado com `otelhttp`. No evaluation-service, o `http.Client` usa
  `otelhttp.NewTransport`, propagando o contexto de trace (`traceparent`) nas
  chamadas ao flag-service e targeting-service. No envio ao SQS, o contexto é
  **injetado nos message attributes**.
- **Python (flag, targeting, analytics):** auto-instrumentação zero-code
  (`opentelemetry-instrument`) cobrindo Flask, requests, psycopg2 e botocore. O
  analytics-service pede `MessageAttributeNames=All` no SQS para **extrair** o
  contexto de trace propagado pelo evaluation-service.

Resultado: uma requisição em `/evaluate` gera um **trace distribuído** que
atravessa evaluation → (flag, targeting) → SQS → analytics, e o **service map**
do Datadog mostra os 5 microsserviços conectados.

---

## 4. Dashboard do Grafana

Dashboard customizado `ToggleMaster — Ecosystem Health`
(`manifests/observability/grafana-dashboards/`), com três seções:

1. **Cluster Resources** — CPU/memória por nó e por namespace de microsserviço.
2. **Microservice Traffic** — taxa de requisições por serviço e **taxa de erro
   5xx (%)** (a métrica que dispara o alerta).
3. **Live Logs (Loki)** — painel de logs em tempo real dos 5 namespaces.

> **Evidência obrigatória:** `<print do dashboard do Grafana>`

---

## 5. Alertas Inteligentes e Self-Healing

### 5.1 Cadeia completa

```
auth-service 5xx > 5% (5 min)
   └─ PrometheusRule "AuthServiceHigh5xxRate"  →  Alertmanager
        ├─ PagerDuty   : abre um incidente (paging do on-call)
        ├─ Discord     : notificação detalhada no canal #incidents
        └─ webhook-adapter (in-cluster)
             └─ GitHub repository_dispatch (self-heal)
                  └─ GitHub Action: kubectl rollout restart deployment/auth-service
```

### 5.2 Componentes

- **Alerta** (`prometheus-rules.yaml`): dispara quando a taxa de HTTP 5xx do
  auth-service passa de 5% em 5 minutos (métrica vinda do OTel).
- **Roteamento** (`alertmanager-config.yaml`): envia o alerta crítico para
  PagerDuty, Discord e o webhook-adapter. Chaves/URLs ficam em um Secret, nunca
  no git.
- **webhook-adapter** (`self-healing/webhook-adapter/`, Go): o Alertmanager não
  consegue enviar cabeçalhos de autenticação nem corpo custom para a API do
  GitHub, então este adaptador traduz o webhook do Alertmanager em uma chamada
  autenticada de `repository_dispatch`.
- **Self-healing** (`.github/workflows/self-heal.yml`): ao receber o dispatch,
  autentica no EKS com as credenciais do Lab e executa
  `kubectl rollout restart deployment/<serviço>`.

### 5.3 Também disponível: alerta no APM

Além do Alertmanager, há a definição de um **monitor no Datadog**
(`observability/datadog/monitors/auth-service-5xx-monitor.json`) para o mesmo
sinal de 5xx, demonstrando que o alerta pode ser criado tanto no Grafana/Prometheus
quanto no APM.

> **Evidências obrigatórias:**
> - `<print do trace distribuído no Datadog APM>`
> - `<print do service map no Datadog>`
> - `<print do alerta em estado "Firing">`
> - `<print do incidente aberto no PagerDuty>`
> - `<print da notificação no Discord>`
> - `<print do log/execução do self-healing (GitHub Action + pod reiniciando)>`

---

## 6. Justificativa técnica das escolhas

### 6.1 Datadog vs. New Relic (APM)

Escolhemos **Datadog**. Ambos têm camada gratuita para educação e integram bem
com OpenTelemetry via OTLP. Pesou a favor do Datadog:
- **Service Map** maduro e de leitura imediata — requisito direto da fase;
- exporter nativo `datadog` no OpenTelemetry Collector (contrib), sem
  necessidade do agente Datadog, mantendo o Collector como hub único;
- integração first-class com PagerDuty (chave de integração direta).

New Relic seria igualmente válido (OTLP nativo, free tier generoso); a decisão foi
pela familiaridade com o service map do Datadog para a demonstração.

### 6.2 PagerDuty vs. OpsGenie (incidentes)

Escolhemos **PagerDuty**. Motivos:
- free tier simples de ativar e integração Events API v2 direta com o
  Alertmanager (receiver `pagerduty_configs`);
- a Atlassian tem direcionado o OpsGenie para planos mais novos, tornando o
  cadastro menos previsível para um projeto acadêmico.

### 6.3 Discord (ChatOps)

Escolhemos **Discord** pela simplicidade: webhook de canal criado em segundos,
sem aprovação de app/admin de workspace. O Alertmanager envia via webhook
compatível com Slack (URL do Discord com sufixo `/slack`).

### 6.4 Self-healing via GitHub Action

Optamos por **GitHub Action disparada por webhook** (em vez de Lambda ou runbook
dedicado) porque:
- é a opção explicitamente sugerida pela fase;
- não exige criação de IAM Role (compatível com o Lab/Academy) — a Action usa as
  credenciais temporárias do Lab;
- é fácil de evidenciar no vídeo (log da execução + pod reiniciando).

---

## 7. Como reproduzir (resumo operacional)

1. `terraform apply` (backend S3 + DynamoDB já provisionados) — cria EKS, RDS,
   ElastiCache, DynamoDB, SQS, ECR e instala ArgoCD + stack base.
2. Criar os Secrets no cluster (ver
   `manifests/observability/alerting/README.md`): `datadog-secret`,
   `grafana-admin`, `alertmanager-toggle-secrets`, `selfheal-github-token`.
3. ArgoCD sincroniza automaticamente os apps de observabilidade
   (`manifests/argocd/observability/`).
4. Gerar carga / injetar erro no auth-service para disparar o alerta e observar a
   cadeia de resposta ativa.

---

## 8. Evidências visuais (anexos)

| # | Evidência | Status |
|---|-----------|--------|
| 1 | Dashboard do Grafana | `<print>` |
| 2 | Trace distribuído no Datadog | `<print>` |
| 3 | Service map no Datadog | `<print>` |
| 4 | Alerta Firing (Grafana/Prometheus ou Datadog) | `<print>` |
| 5 | Incidente no PagerDuty | `<print>` |
| 6 | Notificação no Discord | `<print>` |
| 7 | Self-healing (GitHub Action + pod restart) | `<print>` |
| 8 | ArgoCD gerenciando os apps | `<print>` |
