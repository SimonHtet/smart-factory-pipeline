# Smart Factory Platform

End-to-end manufacturing data platform built for DairyPlus Co., Ltd. (Bangkok) — covering 23 Tetra Pak filler machines across 3 dairy production plants.

This replaced a ฿3M+ quoted MES solution, delivered in 6 months against an 18-month vendor timeline.

---

## What's in Here

| Folder | Description |
|--------|-------------|
| [`pipeline/`](pipeline/) | Python event pipeline — replaces SQL Server triggers, polls PLC data at 1-second intervals, processes machine step transitions |
| [`dashboard/`](dashboard/) | Power BI KPI dashboard — machine efficiency, yield per batch, waste analysis, reviewed weekly at director level |

---

## Architecture

```
PLC Hardware (23 Tetra Pak fillers)
    │
    ▼
SQL Server — T_M_Filler_Process
    │                    │
    │  Python pipeline   │  Power BI DirectQuery
    ▼                    ▼
Processed tables     KPI Dashboard
(step events,        (efficiency, yield,
 splice times,        waste %, batch analysis)
 CIP records)
    │
    ▼
t_log (audit trail)
```

---

## Pipeline

Replaces SQL Server triggers that caused race conditions and row locking under concurrent PLC writes at scale. The Python process owns the state machine explicitly — polling, diffing, routing events to handlers with in-memory cooldowns.

→ See [`pipeline/`](pipeline/) for full details.

---

## Dashboard

Power BI report tracking production KPIs across all machines and plants. Data sourced directly from the factory SQL Server database.

**KPIs tracked:**
- Machine efficiency (FG output / TBA running hour)
- Yield per batch (actual vs. expected)
- Waste volume and category breakdown
- Waste percentage trended over time

→ See [`dashboard/`](dashboard/) for screenshots and DAX measures.

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Event pipeline | Python 3.12, pyodbc |
| Database | SQL Server (on-premise, 3 plants) |
| BI / Reporting | Power BI Desktop + Gateway |
| Source data | Tetra Pak PLC → SQL Server |
| Deployment | Windows Task Scheduler |
