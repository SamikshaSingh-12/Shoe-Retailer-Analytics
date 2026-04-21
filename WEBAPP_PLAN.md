# Webapp Implementation Plan — Footwear Retailer Analytics

**Status:** design complete, not yet implemented
**Owner:** Dhruvil
**Prereqs:** `schema.sql`, `etl.py`, `views.sql`, `roles.sql` already working against local Postgres (`footwear_analytics` DB)

---

## 1. Goal

Build a web application that surfaces all 8 analytics questions (plus the bonus Q9) as interactive dashboards, backed by the existing normalized Postgres schema. Deploy to a public URL so the project can be demoed from any browser.

**Decisions already made (from planning discussion):**

- **Framework:** FastAPI backend + HTML/Chart.js frontend
- **Auth:** none in the UI — webapp uses a single DB connection; role enforcement remains demoed via `verify.py` / SQL / report evidence
- **Scope:** all 8 questions + Q9 bonus
- **Deployment:** cloud (Render.com recommended for FastAPI + Postgres in one dashboard)

**Non-goals:**

- No write endpoints (analytics-only, read-only)
- No ORM — keep SQL visible (fits the course's DB-design focus)
- No frontend build step (CDN-based Chart.js, vanilla JS)
- No user authentication system

---

## 2. Architecture

```
 Browser
   │  fetch JSON, render with Chart.js
   ▼
 Single-page HTML (static, served by FastAPI)
   │  GET /api/q1 … /api/q9, /api/health
   ▼
 FastAPI app (Python 3.12, psycopg2-binary)
   │  SELECT * FROM v_discount_tier_revenue …
   ▼
 PostgreSQL (local for dev; Render Postgres for prod)
```

One HTTP endpoint per view → one chart or table on the frontend. No business logic outside the views — the backend only does thin translation (DB rows → JSON).

---

## 3. File Layout

All new files live under `webapp/`. Existing root-level files (`schema.sql`, `etl.py`, `views.sql`, `roles.sql`, `queries.sql`, `verify.py`) are unchanged and reused.

```
final_project/
├── schema.sql              (existing)
├── etl.py                  (existing)
├── views.sql               (existing)
├── roles.sql               (existing)
├── verify.py               (existing)
└── webapp/                 (new)
    ├── main.py             # FastAPI app: routes + static mount
    ├── db.py               # Connection helper (reads env vars)
    ├── queries.py          # 9 functions, one per view
    ├── static/
    │   ├── index.html      # Single-page dashboard
    │   ├── app.js          # Fetch + Chart.js render
    │   └── styles.css      # Minimal styling
    ├── requirements.txt    # fastapi, uvicorn, psycopg2-binary, python-dotenv
    ├── .env.example        # PGHOST/PGUSER/PGPASSWORD/PGDATABASE/PGPORT
    ├── .gitignore          # .env, __pycache__/, *.pyc
    ├── Procfile            # `web: uvicorn main:app --host 0.0.0.0 --port $PORT`
    └── README.md           # Local dev + deploy instructions
```

---

## 4. Backend

### 4.1 Endpoints


| Method + Path                           | View backing                        | Response shape                                                                                     |
| --------------------------------------- | ----------------------------------- | -------------------------------------------------------------------------------------------------- |
| `GET /`                                 | —                                   | `index.html`                                                                                       |
| `GET /api/health`                       | —                                   | `{"ok": true, "db": "connected"}`                                                                  |
| `GET /api/q1`                           | `v_discount_tier_revenue`           | `[{discount_tier, order_count, total_units, avg_revenue_per_order, total_revenue, avg_rating}, …]` |
| `GET /api/q2`                           | `v_brand_price_sensitivity`         | `[{brand_name, discount_tier, order_count, total_units, total_revenue, avg_revenue_per_order}, …]` |
| `GET /api/q3`                           | `v_category_discount_effectiveness` | as above by category                                                                               |
| `GET /api/q4`                           | `v_channel_pricing_behavior`        | as above by channel                                                                                |
| `GET /api/q5?limit=20`                  | `v_satisfaction_drivers`            | top N rows by avg_rating                                                                           |
| `GET /api/q6`                           | `v_geography_demand`                | all countries                                                                                      |
| `GET /api/q7?category=Running&limit=30` | `v_size_color_demand`               | filterable                                                                                         |
| `GET /api/q8?groupby=year|month`        | `v_temporal_trends`                 | time-aggregated                                                                                    |
| `GET /api/q9`                           | `v_rating_vs_discount`              | tier × rating                                                                                      |


### 4.2 `db.py` — connection helper

```python
import os
import psycopg2
from psycopg2.extras import RealDictCursor
from contextlib import contextmanager

DB_CONFIG = dict(
    host=os.environ.get("PGHOST", "localhost"),
    port=os.environ.get("PGPORT", "5432"),
    dbname=os.environ.get("PGDATABASE", "footwear_analytics"),
    user=os.environ.get("PGUSER", "postgres"),
    password=os.environ.get("PGPASSWORD", "postgres"),
)

@contextmanager
def get_cursor():
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            yield cur
            conn.commit()
    finally:
        conn.close()
```

For production consider `psycopg2.pool.SimpleConnectionPool` if latency matters; fresh-connection-per-request is fine for coursework load.

### 4.3 `queries.py` — one function per view

```python
from db import get_cursor

def _rows(sql, params=None):
    with get_cursor() as cur:
        cur.execute(sql, params or ())
        return [dict(r) for r in cur.fetchall()]

def q1(): return _rows("SELECT * FROM v_discount_tier_revenue")
def q2(): return _rows("SELECT * FROM v_brand_price_sensitivity")
def q3(): return _rows("SELECT * FROM v_category_discount_effectiveness")
def q4(): return _rows("SELECT * FROM v_channel_pricing_behavior")
def q5(limit=20):
    return _rows(
        "SELECT * FROM v_satisfaction_drivers ORDER BY avg_rating DESC LIMIT %s",
        (limit,),
    )
def q6(): return _rows("SELECT * FROM v_geography_demand")
def q7(category="Running", limit=30):
    return _rows("""
        SELECT * FROM v_size_color_demand
        WHERE category_name = %s
        ORDER BY total_units DESC
        LIMIT %s
    """, (category, limit))
def q8(groupby="year"):
    if groupby == "year":
        return _rows("""
            SELECT year, category_name, SUM(total_revenue) AS revenue
            FROM v_temporal_trends
            GROUP BY year, category_name
            ORDER BY year, category_name
        """)
    return _rows("""
        SELECT month, month_name, category_name, SUM(total_revenue) AS revenue
        FROM v_temporal_trends
        GROUP BY month, month_name, category_name
        ORDER BY category_name, month
    """)
def q9(): return _rows("SELECT * FROM v_rating_vs_discount")
```

`Decimal` → `float` conversion handled by custom JSON encoder in FastAPI setup.

### 4.4 `main.py` — FastAPI app

```python
from decimal import Decimal
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import queries, db

app = FastAPI(title="Footwear Retailer Analytics")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["GET"], allow_headers=["*"]
)

class DecimalEncoder(JSONResponse):
    @staticmethod
    def default(o):
        if isinstance(o, Decimal): return float(o)
        raise TypeError

@app.get("/api/health")
def health():
    try:
        with db.get_cursor() as cur:
            cur.execute("SELECT 1")
        return {"ok": True, "db": "connected"}
    except Exception as e:
        raise HTTPException(500, f"db unreachable: {e}")

@app.get("/api/q1")
def api_q1(): return queries.q1()
# … q2 through q9 identically

app.mount("/", StaticFiles(directory="static", html=True), name="static")
```

### 4.5 `requirements.txt`

```
fastapi==0.115.0
uvicorn[standard]==0.32.0
psycopg2-binary==2.9.11
python-dotenv==1.0.1
```

### 4.6 Local dev command

```bash
cd webapp
pip install -r requirements.txt
cp .env.example .env   # fill in local PG credentials
uvicorn main:app --reload --port 8000
# open http://localhost:8000
```

---

## 5. Frontend

### 5.1 Page structure

```
┌───────────────────────────────────────────────────────────┐
│ Global Sports Footwear — Retailer Analytics              │  header
├───────────────────────────────────────────────────────────┤
│ [Pricing]  [Behavior]  [Temporal]  [Bonus]               │  tab nav
├───────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─ Q1 ────────────┐  ┌─ Q2 ─────────────┐                │
│  │ title + desc    │  │ title + desc     │                │
│  │ ┌──────────┐    │  │ ┌──────────┐     │                │
│  │ │ canvas   │    │  │ │ canvas   │     │                │
│  │ └──────────┘    │  │ └──────────┘     │                │
│  │ [show table ▾]  │  │ [show table ▾]   │                │
│  └─────────────────┘  └──────────────────┘                │
│  …                                                        │
└───────────────────────────────────────────────────────────┘
```

### 5.2 Tabs + questions


| Tab      | Questions included                                                                                 |
| -------- | -------------------------------------------------------------------------------------------------- |
| Pricing  | Q1 (tier → revenue), Q2 (brand × tier), Q3 (category × tier), Q4 (channel × tier)                  |
| Behavior | Q5 (top satisfaction combos — table), Q6 (country revenue + income mix), Q7 (size/color × country) |
| Temporal | Q8a (YoY by category, line), Q8b (monthly seasonality, line)                                       |
| Bonus    | Q9 (rating vs tier)                                                                                |


### 5.3 Chart choices (Chart.js)


| Q   | Chart type                                                | Data mapping                                                 |
| --- | --------------------------------------------------------- | ------------------------------------------------------------ |
| Q1  | bar                                                       | tier → total_revenue (secondary axis: avg_revenue_per_order) |
| Q2  | grouped bar                                               | brands on x, grouped by tier                                 |
| Q3  | grouped bar OR heatmap-style colored matrix (use plugin)  |                                                              |
| Q4  | grouped bar                                               | Online vs Retail per tier                                    |
| Q5  | horizontal bar + data table                               | top 10 by avg_rating                                         |
| Q6  | bar (revenue by country) + stacked bar (income mix %)     |                                                              |
| Q7  | dropdown (category) + table of top (size, color) by units |                                                              |
| Q8a | line                                                      | year on x, one line per category                             |
| Q8b | line                                                      | month on x, one line per category                            |
| Q9  | bar                                                       | tier on x, avg_rating as bar height, revenue as tooltip      |


### 5.4 `app.js` skeleton

```javascript
const charts = {};

async function load(endpoint) {
  const r = await fetch(endpoint);
  if (!r.ok) throw new Error(`${endpoint} → ${r.status}`);
  return r.json();
}

function renderTabs() { /* toggle .active on tab buttons + panels */ }

async function renderQ1() {
  const data = await load("/api/q1");
  const ctx = document.getElementById("chart-q1");
  charts.q1 = new Chart(ctx, {
    type: "bar",
    data: {
      labels: data.map(d => d.discount_tier),
      datasets: [{
        label: "Total revenue",
        data: data.map(d => d.total_revenue),
      }],
    },
    options: { responsive: true, maintainAspectRatio: false },
  });
  renderTable("table-q1", data);
}
// … renderQ2() … renderQ9()

document.addEventListener("DOMContentLoaded", () => {
  renderTabs();
  [renderQ1, renderQ2, /* … */ renderQ9].forEach(fn =>
    fn().catch(e => showError(fn.name, e)));
});
```

### 5.5 `index.html` — Chart.js via CDN

```html
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8"/>
    <title>Footwear Retailer Analytics</title>
    <link rel="stylesheet" href="styles.css"/>
  </head>
  <body>
    <header><h1>Global Sports Footwear — Retailer Analytics</h1></header>
    <nav class="tabs">
      <button data-tab="pricing" class="active">Pricing</button>
      <button data-tab="behavior">Behavior</button>
      <button data-tab="temporal">Temporal</button>
      <button data-tab="bonus">Bonus</button>
    </nav>
    <main>
      <section id="pricing" class="panel active">
        <div class="card"><h2>Q1 — Discount Depth vs Revenue</h2>
          <div class="chart-wrap"><canvas id="chart-q1"></canvas></div>
          <details><summary>Data</summary><div id="table-q1"></div></details>
        </div>
        <!-- Q2, Q3, Q4 cards -->
      </section>
      <section id="behavior" class="panel"><!-- Q5, Q6, Q7 --></section>
      <section id="temporal" class="panel"><!-- Q8a, Q8b --></section>
      <section id="bonus" class="panel"><!-- Q9 --></section>
    </main>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <script src="app.js"></script>
  </body>
</html>
```

---

## 6. Cloud Deployment (Render.com)

### 6.1 Why Render

- FastAPI + Postgres in one dashboard
- Free tier covers both (Postgres free tier: 256MB, 90 days — enough for coursework)
- Git-push-to-deploy
- Alternatives: Railway (similar), Fly.io (more config), Supabase + Vercel (2 platforms)

### 6.2 Deploy steps

1. **Push to GitHub.** Create repo, commit everything including `webapp/`. Make sure `.env` is gitignored.
2. **Create Postgres on Render.**
  - Dashboard → New → PostgreSQL → free tier
  - Copy the "External Database URL" (format: `postgres://user:pass@host:port/db`)
3. **Apply schema + data to cloud DB** from local machine:
  ```bash
   export DATABASE_URL="postgres://user:pass@...render.com/footwear_analytics"
   psql "$DATABASE_URL" -f schema.sql
   PGHOST=... PGUSER=... PGPASSWORD=... PGDATABASE=... python3 etl.py
   psql "$DATABASE_URL" -f views.sql
   # roles.sql optional — skip on cloud since UI doesn't use auth
  ```
4. **Create Web Service on Render.**
  - Point at the GitHub repo
  - Root directory: `webapp`
  - Build command: `pip install -r requirements.txt`
  - Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
  - Env vars: `PGHOST`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGPORT` (from step 2)
5. **Verify** — Render gives a public URL like `https://footwear-analytics.onrender.com`. Visit it; all tabs should render.

### 6.3 Render Postgres expiry

Free-tier Postgres expires after 90 days. If longer-term demo access is needed, use **Supabase** (free tier doesn't expire) and keep the web service on Render.

---

## 7. Implementation Order (for later work)

Rough time estimate in parens — assumes familiarity with FastAPI basics.

1. **Scaffold `webapp/`** directory, `requirements.txt`, `.env.example`, `.gitignore`. (10 min)
2. `**db.py` + health endpoint** in `main.py`. Run locally, hit `/api/health`, confirm DB connection. (20 min)
3. `**/api/q1` end-to-end** — `queries.py::q1` + endpoint + minimal `index.html` with one Chart.js bar chart. Proves the full stack. (45 min)
4. **Remaining 8 endpoints** in `queries.py` + `main.py`. Each is ~5 lines. (30 min)
5. **Full frontend** — 4 tabs, 9 cards, all charts + data tables. Bulk of the time. (2–3 hours)
6. **Polish** — loading spinners, error messages, responsive CSS. (30 min)
7. **Local smoke test** — open each tab, verify numbers match `queries.sql` output. (20 min)
8. **GitHub push + Render setup** — repo, Postgres provision, schema/ETL/views apply, web service config. (1 hour)
9. **Production verification** — hit public URL, walk through all tabs, check `/api/health`. Re-run `verify.py` against the cloud DB. (20 min)

**Total:** ~6–7 focused hours.

---

## 8. Verification Checklist

### Local

- `curl http://localhost:8000/api/health` returns `{"ok": true}`
- `curl http://localhost:8000/api/q1 | jq` returns 4 rows (one per discount tier)
- Each `/api/qN` returns the same data as `psql -c "SELECT * FROM v_…"`
- All 9 charts render visibly in browser (no empty canvases)
- Q1 bar heights in order: ~1.72M / 3.26M / 2.87M / 1.23M
- Q6 top country: UAE (~~$1.55M); bottom: Pakistan (~~$1.47M)
- Q8 line chart shows 9 distinct years with per-category lines
- Opening a data table under any chart shows matching rows
- Page loads in under 3 seconds on a fresh reload

### Cloud

- Public URL serves `index.html`
- `/api/health` returns 200 with `db: connected`
- All 4 tabs load without JS errors
- `python3 verify.py` passes all 27 checks against the cloud DB (set `PGHOST` env var)

### Regression

- Local Postgres still works after cloud deploy (no schema drift)
- `queries.sql` still produces the same numbers as the webapp

---

## 9. Open Questions / Risks

- **Cloud cold-start latency.** Render free tier spins down inactive services. First request after idle can take 30–60 s. Acceptable for a course demo; flag in the project write-up.
- **Data-refresh workflow.** If the CSV changes, re-run `etl.py` pointing at the cloud DB. No UI trigger needed (not in scope).
- **Dimension-name casing.** Postgres lowercases unquoted identifiers — verify the `RealDictCursor` keys (e.g., `discount_tier` vs `DiscountTier`) match what the frontend expects.
- **CORS.** Since frontend and backend are same-origin (FastAPI serves the static HTML), CORS is technically not needed. Kept permissive for flexibility if frontend moves to a separate host later.

---

## 10. Summary

This plan turns the completed database project into a shareable web application in roughly a day of focused work. The backend is intentionally thin — every question is already answered by a single SQL view, and the FastAPI layer just translates rows to JSON. The frontend is a single static page using Chart.js via CDN, so there's no build system to maintain. Deployment targets Render's free tier for the fastest path from localhost to a public URL.

Nothing in this plan changes the database design, so the final report's claims remain accurate once the webapp is live.