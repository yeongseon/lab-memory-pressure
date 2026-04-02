# Memory Pressure Lab

An experimental lab to reproduce plan-level performance degradation caused by **aggregate memory pressure** on Azure App Service Plan.

It demonstrates that even if individual apps are not defective, latency increases and intermittent 5xx errors can occur when multiple lightweight apps cumulatively occupy memory on the same Plan.

---

## Directory Structure

```
lab-memory-pressure/
├── app-flask/
│   ├── app.py               Flask app (memory allocation + health/ping/stats endpoints)
│   ├── app.zip              Pre-built self-contained ZIP (deps bundled)
│   ├── requirements.txt     flask, gunicorn
│   └── Dockerfile           Container build (optional)
├── app-node/
│   ├── server.js            Express app (memory allocation + health/ping/stats endpoints)
│   ├── package.json         express
│   └── Dockerfile           Container build for Web App for Containers
├── infra/
│   ├── main.bicep           Main Bicep template (Plan + N Web Apps)
│   ├── main.parameters.json Default parameters
│   └── modules/
│       ├── appservice-plan.bicep
│       ├── webapp.bicep      ZIP deploy (Flask)
│       └── acr.bicep         Azure Container Registry
├── scripts/
│   ├── deploy.sh            Infrastructure deployment + ZIP code deployment
│   ├── scale-apps.sh        Change app count / memory settings
│   ├── traffic-gen.py       Lightweight traffic generation + CSV recording
│   └── monitor.py           Azure Monitor metrics collection + CSV recording
├── docs/
│   └── experiment-log.md    Full experiment log (Flask + Node.js)
├── results/                 CSV data files from all experiments
└── README.md
```

---

## Prerequisites

| Tool | Verification Command |
|---|---|
| Azure CLI ≥ 2.50 | `az version` |
| Bicep CLI | `az bicep version` (or `az bicep install`) |
| jq | `jq --version` |
| Python 3.10+ | `python3 --version` |
| Azure Subscription + Permissions | `az account show` |

```bash
az login
az account set --subscription "<Subscription ID>"
```

---

## Experiment Procedure

### Step 1 — Baseline: 2 apps, ALLOC_MB=100

```bash
export RESOURCE_GROUP="rg-memory-pressure-lab"
export LOCATION="koreacentral"
export NAME_PREFIX="memlabapp"
export PLAN_SKU="B1"
export APP_COUNT=2
export ALLOC_MB=100

bash scripts/deploy.sh
```

Verify normal operation after deployment:

```bash
curl https://memlabapp-1.azurewebsites.net/health
curl https://memlabapp-2.azurewebsites.net/health
```

Start traffic generation (separate terminal):

```bash
python3 scripts/traffic-gen.py \
  --rg rg-memory-pressure-lab \
  --prefix memlabapp \
  --count 2 \
  --interval 15 \
  --output results/baseline.csv
```

Start metrics collection (separate terminal):

```bash
python3 scripts/monitor.py \
  --rg rg-memory-pressure-lab \
  --prefix memlabapp \
  --count 2 \
  --watch 60 \
  --output results/metrics.csv
```

**Expected Results**: Normal response times, no 5xx errors, low CPU, memory usage stabilizes after initial increase.

---

### Step 2 — Gradual Increase of App Count

Observe for at least 10 minutes between steps. If anomalies are observed, stop at that step and record the data.

```bash
# 3 apps
bash scripts/scale-apps.sh 3 100

# 4 apps
bash scripts/scale-apps.sh 4 100

# 5 apps
bash scripts/scale-apps.sh 5 100

# 6 apps
bash scripts/scale-apps.sh 6 100

# 8 apps
bash scripts/scale-apps.sh 8 100

# 10 apps
bash scripts/scale-apps.sh 10 100
```

Update the `--count` argument in traffic-gen and monitor accordingly for each step.

---

### Step 3 — Increase Memory Density (if app count is insufficient)

Keep the app count constant while increasing `ALLOC_MB`.

```bash
bash scripts/scale-apps.sh 6 75
bash scripts/scale-apps.sh 6 100
bash scripts/scale-apps.sh 6 125
bash scripts/scale-apps.sh 6 150
```

Or

```bash
bash scripts/scale-apps.sh 8 75
bash scripts/scale-apps.sh 8 100
```

> **Caution**: On B1, 200MB × 6 or more apps might trigger OOM/crashes first. The goal is to capture the degradation zone, not to induce immediate failure.

---

### Step 4 — Verify Anomalies

Reproduction is considered successful when the following symptoms appear **simultaneously**:

| Symptom | Verification Location |
|---|---|
| Simultaneous latency increase across multiple apps | traffic-gen.py CSV, Azure Portal → Average Response Time |
| Degraded response despite low CPU | Azure Portal → Plan CPU % vs App Response Time |
| Intermittent HTTP 500 / 503 | `!!` lines in traffic-gen.py output, Azure Portal → Http5xx |
| Rising Plan Memory % | monitor.py CSV → MemoryPercentage |
| No clear exceptions in app logs | Azure Portal → Log stream |

---

## Parameter Reference

### `deploy.sh` / `scale-apps.sh` Environment Variables

| Variable | Default Value | Description |
|---|---|---|
| `RESOURCE_GROUP` | `rg-memory-pressure-lab` | Azure Resource Group name |
| `LOCATION` | `koreacentral` | Azure Region |
| `NAME_PREFIX` | `memlabapp` | App name prefix (must be globally unique) |
| `PLAN_SKU` | `B1` | `B1` or `B2` |
| `APP_COUNT` | `2` | Number of apps to deploy |
| `ALLOC_MB` | `100` | Memory allocation per app (MB) |
| `CONTAINER_IMAGE` | `` | ACR image path (if empty, ZIP deployment is used) |

### `traffic-gen.py` Options

| Option | Default Value | Description |
|---|---|---|
| `--rg` | — | Azure Resource Group (auto-fetches hostnames) |
| `--urls` | — | Directly specify URLs (instead of `--rg`) |
| `--prefix` | `memlabapp` | App name prefix |
| `--count` | `10` | Maximum number of apps |
| `--interval` | `15` | Probe interval (seconds) |
| `--output` | `traffic-results.csv` | CSV output file |

### `monitor.py` Options

| Option | Default Value | Description |
|---|---|---|
| `--rg` | — | Azure Resource Group |
| `--prefix` | `memlabapp` | App name prefix |
| `--count` | `10` | Maximum number of apps |
| `--output` | `metrics.csv` | CSV output file |
| `--watch` | `0` | Collection interval (seconds, 0=once) |

---

## Collected Data Items

### Plan Level (monitor.py → metrics.csv)

- `MemoryPercentage` — Aggregate memory utilization of the Plan (Key metric)
- `CpuPercentage` — Aggregate CPU utilization of the Plan
- `HttpQueueLength` — Request queue length
- `DiskQueueLength` — Disk I/O queue length

### App Level (monitor.py → metrics.csv)

- `AverageResponseTime` — Average response time (ms)
- `Http5xx` — Number of 5xx responses
- `Http4xx` — Number of 4xx responses
- `Requests` — Total number of requests
- `MemoryWorkingSet` — Memory usage per app (bytes)

### Traffic Logs (traffic-gen.py → CSV)

- `ts` — Request timestamp (UTC)
- `url` — Target URL
- `status` — HTTP status code
- `elapsed_ms` — Response time (ms)
- `error` — Network error message

---

## Exit Criteria

### Successful Reproduction (No further testing needed)

- Simultaneous increase in average response time across multiple apps in the same Plan
- Intermittent 500/503 errors despite low CPU
- Unstable response patterns while Memory Percentage is high

### Excessive Pressure (Roll back to previous step)

- Repeated container crashes or restart loops
- App OOM becomes the primary phenomenon

Rollback:

```bash
bash scripts/scale-apps.sh <previous_app_count> <previous_ALLOC_MB>
```

---

## Clean Up Resources

```bash
az group delete --name rg-memory-pressure-lab --yes --no-wait
```

---

## Experiment Results (2026-04-02)

### Results Summary

**Phase A: App Count Scaling (ALLOC_MB=50, then 100 for baseline)**

| Config | Plan Memory% | CPU% (stable) | Avg Response | 5xx | Status |
|---|---|---|---|---|---|
| 2 apps × 100MB (baseline) | 76% | 31% | 934ms | 0 | Stable |
| 3 apps × 100MB | - | - | - | - | FAILED (exit code 3) |
| 3 apps × 50MB | 86% | 13-15% | 963ms | 0 | Stable |
| 4 apps × 50MB | 83.6% | 10-18% | 970ms | 0 | Stable |
| 5 apps × 50MB | 85.6% | 15-20% | 984ms | 0 | Stable |
| 6 apps × 50MB | 85.7% | 16-48% | 948ms | 0 | Stable |
| 8 apps × 50MB | 85.7% | 87.2% | 1070ms (apps 1-6) | 6 (apps 7-8) | Partial failure |

**Phase B: Memory Density Scaling (4 apps fixed)**

| Config | Plan Memory% | CPU% (stable) | Avg Response | 5xx | Cold Start |
|---|---|---|---|---|---|
| 4 × 75MB | 85.3% | 14-28% | 986ms | 0 | ~90s |
| 4 × 100MB | 87% | 12-44% | 896ms | 0 | ~120s |
| 4 × 125MB | 89-92% | 13-28% | 915ms | 0 | ~150s |
| 4 × 150MB | 86-91% | 12-46% | 881ms | 0 | ~300s |
| 4 × 175MB | 88-95% | 10-46% | 891ms | 0 | ~360s |
| 6 × 75MB | 93%+ | 100% | N/A | N/A | CRASH (restart loop) |

### Key Findings

1. **Steady-state response remained stable under light load**: Under this low-throughput workload (single probe per app every ~10s), running apps remained responsive even at 95% observed memory utilization (~880-920ms). Note that the ~900ms baseline includes significant network/frontend overhead, which may mask smaller server-side latency changes.

2. **Startup is the vulnerability**: Cold start times increase exponentially — from ~60s at low pressure to ~360s at 95% memory (6x degradation).

3. **Capacity cliff exists**: At 8 apps × 50MB, the plan couldn't start apps 7-8 at all (503 errors, 16s timeouts), while apps 1-6 showed +11-22% latency increase.

4. **Restart cascade = total outage**: When memory hits ~93% and all apps restart simultaneously (6×75MB case), a death spiral occurs — 100% CPU, all apps crash, restart loop.

5. **No steady-state CPU increase from memory pressure alone**: CPU saturation appeared exclusively during startup/restart churn. Once apps stabilized, CPU returned to normal (10-48%) regardless of memory utilization.

6. **Oryx build is a major confound**: Oryx (Azure's build system) consumed 100% CPU for 2-5 minutes during deployment, triggering false degradation signals. Disabling it (SCM_DO_BUILD_DURING_DEPLOYMENT=false) was critical for clean measurements.

### Observed Degradation Zones (Flask / B1 / koreacentral)

> These thresholds were observed in this specific lab configuration and should not be taken as universal B1 guidance.

- **Safe zone**: Plan Memory < 86%, CPU < 30% — all apps responsive, normal cold starts
- **Warning zone**: Plan Memory 86-92% — apps run fine but cold starts slow (2-5 min)
- **Danger zone**: Plan Memory > 92% — new apps may fail to start, restart cascades can cause total outage
- **Critical**: Plan Memory > 93% with simultaneous restarts — death spiral

---

## Interpretation Guide

What this lab demonstrates:
- Plan-wide degradation in lower-tier Plans when resource headroom is insufficient.
- Service quality can degrade due to cumulative memory occupancy even without individual app defects.

What this lab does not directly prove:
- Specific Azure platform defects.
- Specific app code defects.
- The existence of identical thresholds in all environments.
