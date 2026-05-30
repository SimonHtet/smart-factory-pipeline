# Vault — Instructions for Claude Code

## Who I am
- **Name**: Simon (Zhang Zhong Rong)
- **Age**: 26, Myanmar citizen living in Bangkok, Thailand
- **Personality**: ENTP — I like thinking through systems, debating ideas, and building things fast
- **Languages**: English (primary), learning spoken Chinese (can read Pinyin)

## Current role
Manufacturing Systems Engineer at DairyPlus Co., Ltd. (Bangkok)
- Sole SQL Server DBA across 3 dairy production plants
- Self-taught across PLC/WMS/SAP/SQL integration, trigger engineering, traceability systems
- Built 16+ Budibase low-code apps (100+ daily active users)
- Power BI KPIs reviewed at director level
- Background in Industrial Engineering (Mahidol University, 2022)

## Active projects

### Staywise (hotel SaaS)
- Stack: Next.js 14, Supabase (PostgreSQL), Prisma, NextAuth, Vercel
- Target market: Myanmar boutique/independent hotels
- Sales channel: my father's hospitality network (40 years experience)
- Pricing model: per-room
- Key features: 3-step check-in, ReservationDetailPanel (F5/F6/F8 shortcuts), packages/add-ons, night audit, room timeline, teal color scheme
- DB: Vercel + Supabase Transaction Pooler (port 6543) — direct port 5432 fails on Vercel (IPv4 issue)
- Status: deployed, pushing toward pilot-ready

### CargoEye (fleet SaaS)
- Stack: React, Vite, TypeScript
- Pricing: ฿290–590/truck/month, four tiers, Founding Customer program
- Status: paused, pivoted focus to Staywise

### Career transition
- Target: data engineering / MES / Manufacturing IT roles in Bangkok (office-based)
- Target companies: SCG, CP Group, Thai Union
- Headhunters: Robert Walters, Michael Page, Monroe Consulting Thailand
- Tool: career-ops (github.com/santifer/career-ops) for automated job search pipeline
- Key selling point: my MES project replaced a ฿3M+ solution, delivered in 6 months vs 18-month quoted timeline

## Tech stack (overall)
- **Languages**: SQL (SQL Server), JavaScript/TypeScript, Python (learning), PowerShell
- **Frontend**: Next.js, React, Vite, Tailwind, Budibase
- **Backend/DB**: SQL Server, PostgreSQL/Supabase, Prisma, SAP integration
- **DevOps**: Vercel, Git, GitHub
- **BI/Analytics**: Power BI, DAX
- **Hardware/IoT**: PLC integration, WMS, ESP32 (hobby)
- **Hobbies**: drones, 3D printing

## Working preferences
- I prefer dense, information-rich UI (Opera PMS style, not material/rounded)
- I like keyboard shortcuts built into apps
- I want code that is direct and efficient — no unnecessary abstraction
- I self-teach everything — explain things clearly but don't over-simplify
- I work on Windows (no admin rights on work machine — use Scoop/user installs)
- Bangkok timezone (ICT, UTC+7)

## Goals
1. Ship Staywise to first paying pilot hotel
2. Land a data engineering or MES/Manufacturing IT role in Bangkok
3. Build up Python and cloud skills to support career transition

## Notes for Claude Code
- Always check `CLAUDE.md` at session start via `/resume`
- Session logs go in `vault/logs/`
- Project-specific notes go in `vault/<project-name>/`
- Graphify graphs go in `vault/graphify/<project-name>/`
- When Simon says "update" or "update memory" — this means update BOTH the Claude memory files (`~/.claude/projects/.../memory/`) AND the corresponding Obsidian vault note (`vault/<project-name>/`)
