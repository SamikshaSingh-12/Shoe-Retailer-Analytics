"""
ETL: Global Sports Footwear CSV -> PostgreSQL normalized schema.

Usage:
    python3 etl.py

Reads global_sports_footwear_sales_2018_2026.csv and loads into the
footwear_analytics DB. Idempotent: truncates all tables before loading.
"""

import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values

HERE = Path(__file__).parent
CSV_PATH = HERE / "global_sports_footwear_sales_2018_2026.csv"

DB = dict(
    dbname=os.environ.get("PGDATABASE", "footwear_analytics"),
    user=os.environ.get("PGUSER", "postgres"),
    password=os.environ.get("PGPASSWORD", "postgres"),
    host=os.environ.get("PGHOST", "localhost"),
    port=os.environ.get("PGPORT", "5432"),
)


def load_dim(cur, table, name_col, values):
    """Insert distinct values into a lookup table, return {name: id} map."""
    rows = [(v,) for v in sorted(set(values))]
    execute_values(cur, f"INSERT INTO {table} ({name_col}) VALUES %s", rows)
    cur.execute(f"SELECT {name_col}, {table[:-1].lower()}_id FROM {table}")
    # Column naming: brands -> brand_id, categories -> category_id, etc.
    # Not uniform; rewritten below per-table in main().
    return dict(cur.fetchall())


def main():
    df = pd.read_csv(CSV_PATH)
    print(f"Loaded CSV: {len(df):,} rows")

    conn = psycopg2.connect(**DB)
    conn.autocommit = False
    cur = conn.cursor()

    # ---- Clean slate (respect FK order) ----
    cur.execute("""
        TRUNCATE TABLE Orders, Products, DateDim, IncomeLevels,
                       PaymentMethods, Channels, Countries, Genders,
                       Categories, Brands RESTART IDENTITY CASCADE
    """)

    # ---- Lookup tables ----
    def fill_lookup(table, col, pk, values):
        rows = [(v,) for v in sorted(set(values))]
        execute_values(cur, f"INSERT INTO {table} ({col}) VALUES %s", rows)
        cur.execute(f"SELECT {col}, {pk} FROM {table}")
        return dict(cur.fetchall())

    brand_map    = fill_lookup("Brands",         "brand_name",    "brand_id",         df["brand"])
    cat_map      = fill_lookup("Categories",     "category_name", "category_id",      df["category"])
    gender_map   = fill_lookup("Genders",        "gender_name",   "gender_id",        df["gender"])
    channel_map  = fill_lookup("Channels",       "channel_name",  "channel_id",       df["sales_channel"])
    country_map  = fill_lookup("Countries",      "country_name",  "country_id",       df["country"])
    payment_map  = fill_lookup("PaymentMethods", "method_name",   "payment_method_id",df["payment_method"])
    income_map   = fill_lookup("IncomeLevels",   "level_name",    "income_level_id",  df["customer_income_level"])

    print(f"Lookups loaded: brands={len(brand_map)} categories={len(cat_map)} "
          f"genders={len(gender_map)} channels={len(channel_map)} "
          f"countries={len(country_map)} payments={len(payment_map)} incomes={len(income_map)}")

    # ---- Date dimension ----
    df["order_date"] = pd.to_datetime(df["order_date"])
    date_range = pd.date_range(df["order_date"].min(), df["order_date"].max(), freq="D")
    date_rows = [
        (
            int(d.strftime("%Y%m%d")),
            d.date(),
            d.year, d.quarter, d.month, d.strftime("%B"),
            int(d.isocalendar().week),
            (d.weekday() + 1) % 7,  # 0=Sun..6=Sat
            d.weekday() >= 5,       # Sat/Sun
        )
        for d in date_range
    ]
    execute_values(
        cur,
        """INSERT INTO DateDim
           (date_id, full_date, year, quarter, month, month_name,
            week_of_year, day_of_week, is_weekend) VALUES %s""",
        date_rows,
    )
    print(f"DateDim loaded: {len(date_rows):,} days")

    # ---- Products (distinct brand, model, category, gender) ----
    prod_df = df[["brand", "model_name", "category", "gender"]].drop_duplicates()
    prod_rows = [
        (brand_map[r.brand], r.model_name, cat_map[r.category], gender_map[r.gender])
        for r in prod_df.itertuples()
    ]
    execute_values(
        cur,
        """INSERT INTO Products (brand_id, model_name, category_id, gender_id)
           VALUES %s""",
        prod_rows,
    )
    cur.execute("""
        SELECT p.product_id, b.brand_name, p.model_name, c.category_name, g.gender_name
        FROM Products p
        JOIN Brands b     ON b.brand_id = p.brand_id
        JOIN Categories c ON c.category_id = p.category_id
        JOIN Genders g    ON g.gender_id = p.gender_id
    """)
    product_map = {(b, m, c, g): pid for pid, b, m, c, g in cur.fetchall()}
    print(f"Products loaded: {len(product_map):,}")

    # ---- Orders ----
    def build_order_row(r):
        pid = product_map[(r.brand, r.model_name, r.category, r.gender)]
        return (
            r.order_id,
            int(r.order_date.strftime("%Y%m%d")),
            pid,
            country_map[r.country],
            channel_map[r.sales_channel],
            payment_map[r.payment_method],
            income_map[r.customer_income_level],
            int(r.size),
            r.color,
            float(r.base_price_usd),
            float(r.discount_percent),
            int(r.units_sold),
            float(r.customer_rating),
        )

    order_rows = [build_order_row(r) for r in df.itertuples()]
    execute_values(
        cur,
        """INSERT INTO Orders
           (order_id, date_id, product_id, country_id, channel_id,
            payment_method_id, income_level_id, size, color,
            base_price_usd, discount_percent, units_sold, customer_rating)
           VALUES %s""",
        order_rows,
        page_size=1000,
    )
    print(f"Orders loaded: {len(order_rows):,}")

    conn.commit()
    cur.close()
    conn.close()
    print("ETL complete.")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ETL failed: {e}", file=sys.stderr)
        raise
