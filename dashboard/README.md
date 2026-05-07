# Dashboard

Power BI KPI dashboard for monitoring production performance across 3 dairy manufacturing plants (23 Tetra Pak filler machines). Reviewed weekly at director level.

---

## Dashboard Pages

### Machine Efficiency
Tracks **finished goods output per TBA running hour** per machine — the core throughput KPI used to compare machine performance across plants and shifts.

![Machine Efficiency](screenshots/efficiency-per-machine.png)

### Yield per Batch
Monitors **actual yield against expected yield per production batch**, flagging batches that fall below threshold for root cause review.

![Yield per Batch](screenshots/yield-per-batch.png)

### Waste Analysis
Breakdown of **waste volume and waste category** across machines and time periods — used to identify recurring loss patterns and prioritize process improvements.

![Waste Analysis](screenshots/waste-analysis.png)

### Waste Percentage
**Waste as a percentage of total production** — trended over time per machine and plant. Threshold alerts highlight machines exceeding acceptable waste rates.

![Waste Percentage](screenshots/waste-percentage.png)

---

## Data Sources

| Source | Description |
|--------|-------------|
| `T_M_Filler_Process` | Live PLC machine state — step number, running signals, counters |
| `Change paper brik` | Paper roll change events with splice times and feed counter snapshots |
| `Change strip` | Strip change events |
| Production batch tables | Batch records with planned vs. actual yield |

Data is pulled directly from the factory SQL Server database via DirectQuery / scheduled refresh.

---

## Key DAX Measures

```
Machine Efficiency = DIVIDE([Total FG Output (L)], [Total TBA Running Hours])

Waste % = DIVIDE([Total Waste (L)], [Total Production (L)], 0)

Yield Variance = [Actual Yield] - [Expected Yield]
```

---

## Files

| File | Description |
|------|-------------|
| `pbix/manufacturing-kpi-dashboard.pbix` | Main Power BI report file |
| `sql/` | Source queries used in the data model |
| `screenshots/` | Dashboard page screenshots |
