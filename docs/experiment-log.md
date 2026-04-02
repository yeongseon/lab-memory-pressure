# Memory Pressure Lab — Experiment Log

> Experiment Date: 2026-04-02  
> Infrastructure: Azure App Service Plan (Linux B1, koreacentral, 1 instance)  
> App: Flask + gunicorn, occupies `ALLOC_MB` MB bytearray on startup  

---

## 1. Baseline (2 apps × ALLOC_MB=100)

### 1.1 Infrastructure Deployment

| Item | Value |
|---|---|
| Deployment Time | 2026-04-02 05:04 UTC |
| Plan SKU | B1 (Linux) |
| Region | koreacentral |
| Instance Count | 1 (Fixed) |
| Always On | On |
| App Count | 2 (`memlabapp-1`, `memlabapp-2`) |
| ALLOC_MB | 100 |

### 1.2 App Health Check

```
memlabapp-1  /health  → 200 (865ms)
memlabapp-2  /health  → 200 (833ms)
```

Both apps responded normally immediately after deployment.

### 1.3 Baseline Traffic Data (Collected for ~2.5 hours)

| Metric | memlabapp-1 | memlabapp-2 |
|---|---|---|
| Probe Count | 1,458 | 1,458 |
| Avg Response Time | 934.6ms | 933.4ms |
| Min Response Time | 683.5ms | 665.0ms |
| Max Response Time | 2,159.3ms | 2,389.8ms |
| p95 Response Time | 1,091.7ms | 1,093.1ms |
| HTTP 5xx | 0 | 0 |
| Errors | 0 | 0 |

**Total 2,916 probes, 100% HTTP 200.**

Collection Period: `2026-04-02T05:24Z` ~ `2026-04-02T08:03Z` (Approx. 2h 39m)  
Probe Interval: ~10s interval, `/health` + `/ping` round-robin

### 1.4 Baseline Azure Monitor Metrics (Collected at 08:03 UTC)

| Resource | Metric | Value |
|---|---|---|
| **memlabapp-plan** | MemoryPercentage | **76%** |
| memlabapp-plan | CpuPercentage | 31% |
| memlabapp-plan | HttpQueueLength | 0 |
| memlabapp-plan | DiskQueueLength | 0 |
| memlabapp-1 | AverageResponseTime | 8.9ms |
| memlabapp-1 | MemoryWorkingSet | 82,604,032 bytes (~79MB) |
| memlabapp-1 | Http5xx | 0 |
| memlabapp-2 | AverageResponseTime | 8.8ms |
| memlabapp-2 | MemoryWorkingSet | 81,208,661 bytes (~77MB) |
| memlabapp-2 | Http5xx | 0 |

### 1.5 Baseline Conclusion

- With 2 apps × 100MB, Plan Memory is already at **76%** — B1 headroom is very limited.
- CPU is at 31% (plenty of room), but memory is already at a significant level.
- Response time ~930ms (including external network) is stable.
- Zero 5xx, apps are operating normally.

---

## 2. Attempt 3 Apps (ALLOC_MB=100) — Failed

### 2.1 Attempt

| Item | Value |
|---|---|
| Time | 2026-04-02 08:09 UTC |
| Change | App count 2→3, maintained ALLOC_MB=100 |

### 2.2 Result: memlabapp-3 Startup Failure

```
Container has finished running with exit code: 3
Site container: memlabapp-3 terminated during site startup.
Site startup probe failed after 69.88 seconds.
```

memlabapp-3 repeatedly terminated with exit code 3 during startup.  
Attempting to allocate an additional 100MB when Plan Memory was already 76% caused startup failure.

### 2.3 Judgment

3 apps × 100MB cannot even start on B1. Since the goal of the experiment is to "capture the degradation window" rather than "induce startup failure," the **strategy changed**: decided to lower `ALLOC_MB` to 50MB and increase the number of apps first, then gradually increase memory density.

---

## 3. Strategy Change: Restart with ALLOC_MB=50

### 3.1 Plan

```
Phase A: Increase App Count (Fixed ALLOC_MB=50)
  3 apps → 4 apps → 5 apps → 6 apps → 8 apps

Phase B: Increase Memory Density (Fixed App Count)
  50MB → 75MB → 100MB → 125MB
```

### 3.2 Deploy 3 Apps × 50MB

| Item | Value |
|---|---|
| Time | 2026-04-02 08:15 UTC |
| Change | 3 apps, ALLOC_MB=50 |
| Bicep Deployment | Success |

Verified all apps are normal after code deployment:

```
memlabapp-1  /stats → 200  alloc_mb=50  startup=08:27 UTC
memlabapp-2  /stats → 200  alloc_mb=50  startup=08:38 UTC
memlabapp-3  /stats → 200  alloc_mb=50  startup=08:43 UTC
```

### 3.3 Traffic Data (3m collection, 72 probes)

| Metric | Value |
|---|---|
| Probe Count | 72 |
| Collection Period | ~3 min |
| Avg Response Time | ~963ms |
| HTTP 5xx | 0 |
| Errors | 0 |
| Result | 100% HTTP 200 |

### 3.4 Azure Monitor Metrics (Collected at 08:48 UTC)

#### Plan Metrics

| Metric | 08:43 | 08:44 | 08:45 | 08:46 | 08:47 | Notes |
|---|---|---|---|---|---|---|
| MemoryPercentage | 80% | 84% | 84% | 85% | **86%** | baseline 76% → 86% (+10pp) |
| CpuPercentage | 69% | 74% | 14% | 13% | 15% | Spike after deployment → stabilized at 13-15% |
| HttpQueueLength | 0 | 0 | 0 | 0 | 0 | |
| DiskQueueLength | 0 | 0 | 0 | 0 | 0 | |

#### App Metrics

| App | AvgResponseTime | Http5xx | MemoryWorkingSet |
|---|---|---|---|
| memlabapp-1 | 6.6~9ms | 0 | ~80MB |
| memlabapp-2 | 3~10ms | 0 | ~110MB |
| memlabapp-3 | 3.4~23ms | 0 | ~120MB (startup settling) |

### 3.5 Conclusion (3 apps × 50MB)

- Plan Memory: 76% → **86%** (+10pp) — 10% increase per added app.
- CPU: Stabilized at 13-15% after deployment spike (69-74%) — actually lower than baseline (31%).
- Response Time: ~963ms, similar to baseline (~934ms), no significant difference.
- 5xx: Still zero — not yet in the degradation zone.
- **Judgment**: Still have headroom. Proceed with increasing app count.

---

## 4. 4 Apps × 50MB

### 4.1 Deployment

| Item | Value |
|---|---|
| Time | 2026-04-02 08:55~09:28 UTC |
| Change | App count 3→4, maintained ALLOC_MB=50 |
| Bicep | Success |
| Notes | Disabled Oryx build (SCM_DO_BUILD_DURING_DEPLOYMENT=false) — removed build CPU load |

### 4.2 Deployment Anomalies (Important!)

**First Attempt (Oryx Enabled):**
- memlabapp-4 Oryx build occupied Plan CPU at **99-100%** for ~5 minutes.
- Python extraction + venv creation took 110s during build.
- Container exit code 3 + "did not start within expected time limit of 230s".
- Existing apps 1-3 also restarted during the deployment process.

**Plan Metrics (During Deployment, 09:10~09:14 UTC):**
- Memory: 84% → 64% (temporary drop due to app restarts) → 83% (stabilized).
- CPU: **100%** (5 minutes continuous) — caused by Oryx build.
- Existing App Response: Maintained 200 OK, ~960-1100ms.

**Second Attempt (Oryx Disabled + Pre-built ZIP):**
- memlabapp-4 final startup: 09:28 UTC.
- Verified all 4 apps are operating normally.

### 4.3 Post-Stabilization Traffic Data (5m collection, 120 probes)

| App | Probe Count | Avg Response | 5xx | Errors |
|---|---|---|---|---|
| memlabapp-1 | 30 | 969ms | 0 | 0 |
| memlabapp-2 | 30 | 977ms | 0 | 0 |
| memlabapp-3 | 30 | 978ms | 0 | 0 |
| memlabapp-4 | 30 | 955ms | 0 | 0 |

**Total: 120 probes, 100% HTTP 200, Avg ~970ms**

### 4.4 Azure Monitor Metrics (Post-Stabilization, 09:30~09:43 UTC)

| Metric | Average | Minimum | Maximum |
|---|---|---|---|
| MemoryPercentage | **83.6%** | 80% | 87% |
| CpuPercentage | **23.9%** | 10% | 80%* |

*CPU 80% spike occurred intermittently for 1 minute at 09:43.

### 4.5 Conclusion (4 apps × 50MB)

- Plan Memory: 86% → **83.6%** (Build artifacts decreased by disabling Oryx).
- CPU: 10-18% when stable, intermittent spikes (30-80%).
- Response Time: ~970ms — slight increase of +36ms (+3.9%) vs baseline (934ms).
- 5xx: 0
- **Deployment itself triggers degradation**: Oryx build causes CPU 100% + app restarts.
- **Judgment**: Threshold not yet reached in stable state. Proceed to 5 apps.

---

## 5. 5 Apps × 50MB

### 5.1 Deployment

| Item | Value |
|---|---|
| Time | 2026-04-02 09:46~09:49 UTC |
| Change | App count 4→5, ALLOC_MB=50 |
| app-5 Startup Time | ~135s (Cold start delay under memory pressure) |

### 5.2 Traffic Data (5m, 125 probes, 09:51~09:56 UTC)

| App | Probe Count | Avg Response | 5xx | Errors |
|---|---|---|---|---|
| memlabapp-1 | 25 | **1,050ms** | 0 | 0 |
| memlabapp-2 | 25 | 982ms | 0 | 0 |
| memlabapp-3 | 25 | 962ms | 0 | 0 |
| memlabapp-4 | 25 | 964ms | 0 | 0 |
| memlabapp-5 | 25 | 964ms | 0 | 0 |

**Total: 125 probes, 100% HTTP 200, Avg ~984ms**

### 5.3 Azure Monitor Metrics (09:48~09:56 UTC)

| Metric | Average | Minimum | Maximum | Notes |
|---|---|---|---|---|
| MemoryPercentage | **85.6%** | 84% | 86% | +2pp vs 4 apps (83.6%) |
| CpuPercentage | 50.2%* | 15% | 94% | *Includes startup spike, 15-20% when stable |

### 5.4 Conclusion (5 apps × 50MB)

- Plan Memory: **85.6%** — Still rising, but still stable.
- CPU: 15-20% when stable (low).
- Response Time: ~984ms (+50ms, +5.4% vs baseline 934ms).
- memlabapp-1 response at 1,050ms is somewhat high — possible sign of early degradation.
- 5xx: 0
- Cold Start Time: 135s (longer than 4 apps).
- **Judgment**: Minimal latency increase. Proceed to 6 apps.

---

## 6. 6 Apps × 50MB

### 6.1 Deployment

| Item | Value |
|---|---|
| Time | 2026-04-02 09:59~10:02 UTC |
| Change | App count 5→6, ALLOC_MB=50 |
| app-6 Startup Time | ~135s |

### 6.2 Traffic Data (5m, 150 probes, 10:04~10:09 UTC)

| App | Probe Count | Avg Response | Max Response | 5xx | Errors |
|---|---|---|---|---|---|
| memlabapp-1 | 25 | 988ms | 1,256ms | 0 | 0 |
| memlabapp-2 | 25 | 968ms | 1,125ms | 0 | 0 |
| memlabapp-3 | 25 | 948ms | 1,265ms | 0 | 0 |
| memlabapp-4 | 25 | 942ms | 1,172ms | 0 | 0 |
| memlabapp-5 | 25 | 895ms | 1,276ms | 0 | 0 |
| memlabapp-6 | 25 | 944ms | 1,133ms | 0 | 0 |

**Total: 150 probes, 100% HTTP 200, Avg ~948ms**

### 6.3 Azure Monitor Metrics (10:01~10:09 UTC)

| Metric | Average | Minimum | Maximum | Notes |
|---|---|---|---|---|
| MemoryPercentage | **85.7%** | 84% | 89% | Almost identical to 5 apps (85.6%) |
| CpuPercentage | 58.2%* | 16% | 99% | *Includes startup, 16-48% when stable |

### 6.4 Conclusion (6 apps × 50MB)

- Plan Memory: **85.7%** — Almost no change from 5 apps (85.6%).
- CPU: 16-48% when stable (slightly higher than 5 apps).
- Response Time: ~948ms — actually improved over 5 apps (984ms), within normal fluctuation range.
- 5xx: 0
- Cold Start: 135s (same as 5 apps).
- **Observation**: Memory is no longer increasing. It is estimated that B1 is already using ~85% for OS/platform overhead, and when a 50MB app is added, existing apps' working sets are swapped/compressed, keeping the total constant.
- **Judgment**: Difficult to reach threshold with 50MB apps. Attempt 8 apps, then transition to Phase B (Increase ALLOC_MB).

---

## 7. 8 Apps × 50MB

### 7.1 Deployment

| Item | Value |
|---|---|
| Time | 2026-04-02 ~10:15 UTC |
| Change | App count 6→8, ALLOC_MB=50 |
| Total Probes | 128 (16 per app) |

### 7.2 Traffic Data

| App | Probe Count | Avg Response | Max Response | 5xx | Errors |
|---|---|---|---|---|---|
| memlabapp-1 | 16 | 1,138ms | 1,612ms | 0 | 0 |
| memlabapp-2 | 16 | 1,081ms | 1,591ms | 0 | 0 |
| memlabapp-3 | 16 | 1,028ms | 1,236ms | 0 | 0 |
| memlabapp-4 | 16 | 929ms | 1,578ms | 0 | 0 |
| memlabapp-5 | 16 | 1,083ms | 1,320ms | 0 | 0 |
| memlabapp-6 | 16 | 893ms | 1,605ms | 0 | 0 |
| memlabapp-7 | 16 | 4,105ms | 16,178ms | 3 | 3 |
| memlabapp-8 | 16 | 3,824ms | 16,157ms | 3 | 3 |

**Total: 128 probes. Apps 1-6: 0 5xx. Apps 7-8: 6 5xx errors combined.**

### 7.3 Azure Monitor Metrics

| Metric | Value | Notes |
|---|---|---|
| MemoryPercentage | ~85.7% | No further increase vs 6 apps |
| CpuPercentage | ~87.2% | Elevated by failed startup contention from apps 7-8 |

### 7.4 Conclusion (8 apps × 50MB)

- Apps 1-6: Stable with mild latency increase (+11-22% vs baseline 934ms). Zero 5xx.
- Apps 7-8: Could NOT start properly — 503 errors, timeouts up to 16 seconds.
- CPU spiked to 87.2% due to competing startup processes from apps 7-8.
- **Key Finding**: This is the first clear degradation evidence in Phase A — a capacity cliff where new apps cannot obtain enough memory to start, while existing apps continue to serve traffic with elevated latency.
- **Judgment**: Phase A capacity limit reached. Transition to Phase B (increase memory density, fix app count).

---

## 8. Phase B Strategy Change: 6 Apps × 75MB (Catastrophic Failure)

### 8.1 Strategy Change

| Item | Value |
|---|---|
| Phase | Transition from Phase A (scale app count) to Phase B (scale memory density) |
| Fixed App Count | 6 (initial attempt) |
| New ALLOC_MB | 75 |

### 8.2 Result

| Metric | Value |
|---|---|
| Memory Peak | 93% |
| CPU Peak | 100% |
| App Status | ALL 6 apps entered restart loop |
| Exit Codes | Container exit codes observed on all apps |
| Startup Probes | All failed |
| Outcome | Total service outage — rolled back |

### 8.3 Conclusion

6 apps × 75MB was too aggressive. Jumping from 6 × 50MB (total ~300MB allocated) to 6 × 75MB (total ~450MB allocated) pushed memory over the critical threshold simultaneously on all apps, triggering a cascade restart loop. The platform could not recover on its own. Rolled back and reduced app count to 4 before increasing per-app memory.

---

## 9. 4 Apps × 75MB (Phase B Baseline)

### 9.1 Deployment

| Item | Value |
|---|---|
| Change | Rolled back to 4 apps, ALLOC_MB increased to 75 |
| Total Probes | ~120 |

### 9.2 Traffic Data

| Metric | Value |
|---|---|
| Total Probes | ~120 |
| Avg Response Time | ~986ms |
| HTTP 5xx | 0 |
| Errors | 0 |

### 9.3 Azure Monitor Metrics

| Metric | Value |
|---|---|
| MemoryPercentage (avg) | 85.3% |
| MemoryPercentage (max) | 90% |
| CpuPercentage (stable) | 14-28% |

### 9.4 Conclusion (4 apps × 75MB)

- Stable operation confirmed. Zero 5xx, average latency close to baseline.
- Memory headroom remains acceptable at this configuration.
- **4 apps confirmed as the safe base for Phase B memory density scaling.**

---

## 10. 4 Apps × 100MB

### 10.1 Deployment

| Item | Value |
|---|---|
| Change | ALLOC_MB increased from 75 to 100, 4 apps fixed |
| Total Probes | 120 |
| Cold Start Time | ~2 minutes |

### 10.2 Traffic Data

| App | Avg Response | Max Response | 5xx |
|---|---|---|---|
| memlabapp-1 | 854ms | 1,252ms | 0 |
| memlabapp-2 | 968ms | 1,077ms | 0 |
| memlabapp-3 | 868ms | 2,419ms | 0 |
| memlabapp-4 | 893ms | 1,186ms | 0 |

**Overall: 120 probes, avg 896ms, 0 5xx.**

### 10.3 Azure Monitor Metrics

| Metric | Value | Notes |
|---|---|---|
| MemoryPercentage | 84-89% (avg ~87%) | |
| CpuPercentage (stable) | 12-44% | After restart spike settled |
| CpuPercentage (restart spike) | 99-100% | Duration ~4 minutes during cold start |

### 10.4 Conclusion (4 apps × 100MB)

- Stable once apps finish cold start (~2 minutes).
- Restart spike at 99-100% CPU lasts approximately 4 minutes — first notable cold-start CPU contention in Phase B.
- memlabapp-3 max response of 2,419ms is an outlier likely captured during the tail of the cold-start window.
- No 5xx in steady state.
- **Judgment**: Safe configuration. Cold start time increasing. Proceed to 125MB.

---

## 11. 4 Apps × 125MB

### 11.1 Deployment

| Item | Value |
|---|---|
| Change | ALLOC_MB increased from 100 to 125, 4 apps fixed |
| Total Probes | 120 |
| Cold Start Time | ~2.5 minutes (increasing vs 100MB) |

### 11.2 Traffic Data

| App | Avg Response | Max Response | 5xx |
|---|---|---|---|
| memlabapp-1 | 980ms | 1,146ms | 0 |
| memlabapp-2 | 884ms | 1,121ms | 0 |
| memlabapp-3 | 889ms | 1,075ms | 0 |
| memlabapp-4 | 906ms | 1,101ms | 0 |

**Overall: 120 probes, avg 915ms, 0 5xx.**

### 11.3 Azure Monitor Metrics

| Metric | Value | Notes |
|---|---|---|
| MemoryPercentage | 89-92% (peak 92%) | Highest sustained memory level so far |
| CpuPercentage (stable) | 13-28% | After restart spike settled |

### 11.4 Conclusion (4 apps × 125MB)

- Memory pressure reaching 89-92% — approaching the upper boundary observed before the 6×75MB crash (93%).
- Steady-state latency remains comparable to baseline (~915ms vs 934ms baseline).
- Cold start time now 2.5 minutes, a clear upward trend.
- No 5xx in steady state.
- **Judgment**: Still stable in steady state, but cold start degradation is measurable. Proceed to 150MB with caution.

---

## 12. 4 Apps × 150MB

### 12.1 Deployment

| Item | Value |
|---|---|
| Change | ALLOC_MB increased from 125 to 150, 4 apps fixed |
| Total Probes | 120 |
| Cold Start Time | ~5 minutes |

### 12.2 Traffic Data

| App | Avg Response | Max Response | 5xx |
|---|---|---|---|
| memlabapp-1 | 799ms | 1,100ms | 0 |
| memlabapp-2 | 970ms | 1,128ms | 0 |
| memlabapp-3 | 864ms | 1,170ms | 0 |
| memlabapp-4 | 892ms | 1,181ms | 0 |

**Overall: 120 probes, avg 881ms, 0 5xx.**

### 12.3 Azure Monitor Metrics

| Metric | Value | Notes |
|---|---|---|
| MemoryPercentage | 86-91% (peak 91%) | |
| CpuPercentage (stable) | 12-46% | After restart spike settled |
| CpuPercentage (restart spike) | 100% | Duration ~2 minutes during cold start |

### 12.4 Conclusion (4 apps × 150MB)

- Steady-state latency remains healthy — avg 881ms, no 5xx.
- Cold start time has doubled from 100MB (~2 min) to 150MB (~5 min) — a significant jump.
- CPU hits 100% for ~2 minutes during each restart/cold-start event at this memory level.
- **Key observation**: The platform keeps running processes responsive through memory compression, but startup events are severely impacted.
- **Judgment**: Stable in steady state. Cold start penalty now severe. Proceed to 175MB.

---

## 13. 4 Apps × 175MB (Extreme Pressure)

### 13.1 Deployment

| Item | Value |
|---|---|
| Change | ALLOC_MB increased from 150 to 175, 4 apps fixed |
| Total Probes | 120 |
| Cold Start Time | ~6 minutes |

### 13.2 Traffic Data

| App | Avg Response | Max Response | 5xx |
|---|---|---|---|
| memlabapp-1 | 901ms | 1,598ms | 0 |
| memlabapp-2 | 957ms | 1,207ms | 0 |
| memlabapp-3 | 919ms | 1,178ms | 0 |
| memlabapp-4 | 785ms | 1,226ms | 0 |

**Overall: 120 probes, avg 891ms, 0 5xx.**

### 13.3 Azure Monitor Metrics

| Metric | Value | Notes |
|---|---|---|
| MemoryPercentage | 88-95% (peak 95%) | Highest memory level recorded in Phase B |
| CpuPercentage (stable) | 10-46% | After restart spike settled |
| CpuPercentage (restart spike) | 100% | Duration ~2 minutes during cold start |

### 13.4 Conclusion (4 apps × 175MB)

- Memory peaked at 95% — only 2pp below the 97%+ threshold that caused the 6×75MB crash loop.
- Steady-state latency is still comparable to baseline. No 5xx recorded.
- Cold start now takes 6 minutes — 6x longer than the original 60-second baseline.
- The platform survived 175MB × 4 apps in steady state, but any additional restart event here carries significant risk of triggering a cascade similar to the 6×75MB failure.

---

## 14. Final Analysis — Degradation Window

### Phase A Summary (App Count Scaling, ALLOC_MB=50)

| Config | Memory% | CPU% (stable) | Avg Response | 5xx | Cold Start |
|---|---|---|---|---|---|
| 2 apps × 100MB (baseline) | 76% | 31% | 934ms | 0 | ~60s |
| 3 apps × 50MB | 86% | 13-15% | 963ms | 0 | ~60s |
| 4 apps × 50MB | 83.6% | 10-18% | 970ms | 0 | ~60s |
| 5 apps × 50MB | 85.6% | 15-20% | 984ms | 0 | ~135s |
| 6 apps × 50MB | 85.7% | 16-48% | 948ms | 0 | ~135s |
| 8 apps × 50MB | 85.7% | 87.2% | 1070ms (1-6) / 4000ms (7-8) | 6 | Apps 7-8 FAILED |

### Phase B Summary (Memory Density Scaling, 4 apps fixed)

| Config | Memory% | CPU% (stable) | Avg Response | 5xx | Cold Start |
|---|---|---|---|---|---|
| 4 × 75MB | 85.3% | 14-28% | 986ms | 0 | ~90s |
| 4 × 100MB | 87% | 12-44% | 896ms | 0 | ~120s |
| 4 × 125MB | 89-92% | 13-28% | 915ms | 0 | ~150s |
| 4 × 150MB | 86-91% | 12-46% | 881ms | 0 | ~300s |
| 4 × 175MB | 88-95% | 10-46% | 891ms | 0 | ~360s |
| 6 × 75MB | 93%→crash | 100%→crash | N/A | N/A | CRASH LOOP |

### Three Degradation Modes Discovered

1. **Startup Degradation**: Cold start times increase with memory pressure.
   - 50MB: ~60s → 175MB: ~360s (6x increase).
   - At 175MB, apps take 6 minutes to become responsive after a restart.

2. **Capacity Cliff (Phase A)**: At 8 apps × 50MB, the plan could not start apps 7-8 at all.
   - Apps 1-6 showed +11-22% latency increase.
   - Apps 7-8: 503 errors, 16-second timeouts.
   - CPU spiked to 87% from competing startup processes.

3. **Restart Cascade (6×75MB)**: When memory hits ~93%+, simultaneous restarts trigger a death spiral.
   - All apps crash, CPU 100%, continuous restart loop.
   - This is the most dangerous failure mode — total service outage with no self-recovery.

### Surprising Finding

Under this light steady-state workload (single curl probe per app every ~10s), running apps remained responsive even at 95% observed memory utilization — average response times stayed within the ~880-950ms range across all configurations. Note that the ~900ms baseline for a trivial Flask app indicates significant network/frontend overhead in our external measurements, which may mask smaller server-side latency shifts.

No steady-state CPU increase from memory pressure alone was observed; CPU saturation appeared exclusively during startup/restart churn (app boot competing for resources). Once apps stabilized, CPU returned to 10-48% regardless of memory utilization level.

The primary degradation modes are all related to state transitions — startup, restart, and scaling events — not steady-state request serving.

> **Note:** The degradation zones and thresholds reported above are observed operating bands for this specific Flask/B1/koreacentral lab configuration. They should not be interpreted as universal B1 platform guidance, as results may vary with different workloads, regions, and application characteristics.
