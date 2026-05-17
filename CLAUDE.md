# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Context

SCC-541 – Laboratório de Bases de Dados (ICMC/USP São Carlos, 1º Sem 2026).  
Trabalho Prático T4: exercícios sobre visões (views) no PostgreSQL, usando uma base F1 + dados geográficos (cidades, países, aeroportos).

The single deliverable is `t4_views.sql` — all exercises are in this one script.

## Running the Script

### With Docker (recommended)

```bash
# First time: build image and load data (takes a few minutes)
cd docker-labbd
docker compose up --build

# Execute the T4 script against the running container
docker exec -i labbd_postgres psql -U labbd -d labbd < t4_views.sql

# Or copy the file in and run interactively
docker cp t4_views.sql labbd_postgres:/tmp/
docker exec -it labbd_postgres psql -U labbd -d labbd -f /tmp/t4_views.sql

# Connect interactively
docker exec -it labbd_postgres psql -U labbd -d labbd

# Stop (data persists)
docker compose down

# Wipe and reload from scratch
docker compose down -v && docker compose up --build
```

Connection info: `host=localhost port=5432 db=labbd user=labbd password=labbd123`

### Without Docker

```bash
psql -U <usuario> -d <banco> -f t4_views.sql
```

PostgreSQL 13+ required. Extensions `cube` and `earthdistance` must be available (the script installs them with `CREATE EXTENSION IF NOT EXISTS`).

## Database Schema

Two domains joined together:

**Geographic:** `continents → countries → cities → airports` (also `airport_types`, `time_zones`, `feature_codes`, language tables)

**Formula 1:** `seasons`, `circuits → cities`, `constructors`, `drivers`, `races`, `results`, `qualifying`, `standings` (normalized into `driver_standings` / `constructor_standings`)

Key nullable FK: `airports.city_id` — many airports have no city linked; the exercises exploit this.

## Views Implemented

| Exercise | View | Type | Key detail |
|---|---|---|---|
| 1 | `Aeroportos_Brasileiros` | Materialized | Requires `REFRESH MATERIALIZED VIEW` after base-table changes |
| 2 | `Aeroportos_sem_cidades` | Regular | `airports WHERE city_id IS NULL` |
| 2 | `Cidades_brasileiras` | Regular | Brazilian cities with `population >= 100000` |
| 3 | `Circuitos_completa` | Regular | Uses LEFT JOINs so all 76 circuits appear even without a city |
| 4 | `Problemas_aeroportos` | Regular | Airports from Ex.2 within 10 km of a city from Ex.2 (via `earth_distance`) |
| 5 | `Correcao_aeroportos` | Regular (updatable) | Single-table view on `airports`; UPDATE through it sets `city_id` |

## Key Patterns

- **Geographic distance** uses `earth_distance(ll_to_earth(lat, lng), ll_to_earth(lat, lng)) / 1000.0` (result in km). Requires `cube` + `earthdistance` extensions.
- **CTEs (`WITH`)** isolate distance calculations to avoid repeating `earth_distance` expressions.
- **`DISTINCT ON (id) … ORDER BY id, distancia_km`** selects the single closest city per airport (PostgreSQL-specific, Exercise 5).
- `Correcao_aeroportos` is kept as a simple `SELECT … FROM airports WHERE id IN (…)` — no JOINs — so PostgreSQL treats it as an automatically updatable view (AUVis), allowing `UPDATE` directly on the view.