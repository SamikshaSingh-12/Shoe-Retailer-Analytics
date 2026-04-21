# Footwear Retailer Analytics — Webapp

Single-page dashboard surfacing the 9 analytics views over the `footwear_analytics` Postgres schema.

Stack: **FastAPI** (Python) + **Chart.js** (vanilla JS, CDN) + **PostgreSQL**.

## Local development

```bash
cd webapp
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env      # edit PG credentials
uvicorn main:app --reload --port 8000
```

Open <http://localhost:8000>.

Prereqs: `schema.sql`, `etl.py`, `views.sql` already applied to your local DB.

## Endpoints

| Path | Backing view |
| ---- | ------------ |
| `GET /api/health` | — |
| `GET /api/q1` | `v_discount_tier_revenue` |
| `GET /api/q2` | `v_brand_price_sensitivity` |
| `GET /api/q3` | `v_category_discount_effectiveness` |
| `GET /api/q4` | `v_channel_pricing_behavior` |
| `GET /api/q5?limit=20` | `v_satisfaction_drivers` |
| `GET /api/q6` | `v_geography_demand` |
| `GET /api/q7?category=Running&limit=30` | `v_size_color_demand` |
| `GET /api/q8?groupby=year\|month` | `v_temporal_trends` |
| `GET /api/q9` | `v_rating_vs_discount` |
| `GET /api/categories` | distinct categories (for Q7 dropdown) |

## Deploy to Render.com

1. Push repo to GitHub (ensure `.env` is gitignored).
2. **Create Postgres** on Render → copy the External Database URL.
3. **Apply schema/ETL/views** to cloud DB from local machine:

   ```bash
   export PGHOST=... PGUSER=... PGPASSWORD=... PGDATABASE=... PGPORT=...
   psql "$DATABASE_URL" -f ../schema.sql
   python3 ../etl.py
   psql "$DATABASE_URL" -f ../views.sql
   ```

4. **Create Web Service** on Render → point at repo:
   - Root directory: `webapp`
   - Build: `pip install -r requirements.txt`
   - Start: `uvicorn main:app --host 0.0.0.0 --port $PORT`
   - Env vars: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`.

5. Visit the public URL; verify `/api/health` returns `{"ok": true}`.

## Notes

- No auth in the UI — role enforcement is demoed via `verify.py` / `roles.sql`.
- Read-only — no write endpoints.
- Free-tier Render Postgres expires after 90 days; use Supabase for longer demo access.
