"""
Verification suite for the footwear_analytics DB.

Runs:
  1. Row-count integrity (all expected totals)
  2. Constraint rejection (bad inserts MUST fail)
  3. View correctness vs pandas recomputation from raw CSV
  4. Normalization smell-test (no brand_name etc. outside dim tables)
  5. Role access enforcement (smoke)

Usage:
    python3 verify.py
"""

import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
from psycopg2.errors import CheckViolation, ForeignKeyViolation

HERE = Path(__file__).parent
CSV_PATH = HERE / "global_sports_footwear_sales_2018_2026.csv"

DB = dict(
    dbname="footwear_analytics",
    user="postgres",
    password=os.environ.get("PGPASSWORD", "postgres"),
    host="localhost",
    port="5432",
)

FAIL = 0
PASS = 0


def check(label, cond, detail=""):
    global PASS, FAIL
    status = "PASS" if cond else "FAIL"
    if cond:
        PASS += 1
    else:
        FAIL += 1
    print(f"  [{status}] {label}" + (f"  — {detail}" if detail else ""))


def section(name):
    print(f"\n=== {name} ===")


def main():
    conn = psycopg2.connect(**DB)
    cur = conn.cursor()

    # -----------------------------------------------------------
    section("1. Row-count integrity")
    # -----------------------------------------------------------
    expected = {
        "orders": 30000,
        "brands": 6,
        "categories": 5,
        "genders": 3,
        "channels": 2,
        "countries": 6,
        "paymentmethods": 4,
        "incomelevels": 3,
    }
    for tbl, n in expected.items():
        cur.execute(f"SELECT COUNT(*) FROM {tbl}")
        got = cur.fetchone()[0]
        check(f"{tbl} = {n}", got == n, f"got {got}")

    cur.execute("SELECT COUNT(*) FROM orders WHERE date_id IS NULL OR product_id IS NULL")
    null_fk = cur.fetchone()[0]
    check("no NULLs in Orders FK columns", null_fk == 0, f"{null_fk} nulls")

    # -----------------------------------------------------------
    section("2. Constraint rejection (each bad insert MUST fail)")
    # -----------------------------------------------------------
    def must_fail(label, sql, params, expected_err):
        global PASS, FAIL
        conn.rollback()  # clear prior aborted tx
        try:
            cur.execute(sql, params)
            conn.commit()
            print(f"  [FAIL] {label} — INSERT unexpectedly succeeded")
            FAIL += 1
        except expected_err as e:
            print(f"  [PASS] {label} — rejected: {type(e).__name__}")
            PASS += 1
            conn.rollback()
        except Exception as e:
            print(f"  [FAIL] {label} — wrong error: {type(e).__name__}: {e}")
            FAIL += 1
            conn.rollback()

    # Need valid FKs for the bad-value inserts to test the CHECK
    cur.execute("SELECT MIN(date_id), MIN(product_id) FROM orders")
    d_id, p_id = cur.fetchone()
    # And get one of each lookup id
    cur.execute("SELECT country_id FROM countries LIMIT 1")
    co_id = cur.fetchone()[0]
    cur.execute("SELECT channel_id FROM channels LIMIT 1")
    ch_id = cur.fetchone()[0]
    cur.execute("SELECT payment_method_id FROM paymentmethods LIMIT 1")
    pm_id = cur.fetchone()[0]
    cur.execute("SELECT income_level_id FROM incomelevels LIMIT 1")
    il_id = cur.fetchone()[0]

    base_ins = """
        INSERT INTO Orders (order_id, date_id, product_id, country_id, channel_id,
                            payment_method_id, income_level_id, size, color,
                            base_price_usd, discount_percent, units_sold, customer_rating)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'Black', %s, %s, %s, %s)
    """
    must_fail(
        "discount_percent = 150 rejected",
        base_ins,
        ("BAD_DISC", d_id, p_id, co_id, ch_id, pm_id, il_id, 8, 100, 150, 1, 4.0),
        CheckViolation,
    )
    must_fail(
        "units_sold = 0 rejected",
        base_ins,
        ("BAD_UNITS", d_id, p_id, co_id, ch_id, pm_id, il_id, 8, 100, 10, 0, 4.0),
        CheckViolation,
    )
    must_fail(
        "customer_rating = 9.0 rejected",
        base_ins,
        ("BAD_RATING", d_id, p_id, co_id, ch_id, pm_id, il_id, 8, 100, 10, 1, 9.0),
        CheckViolation,
    )
    must_fail(
        "base_price = -50 rejected",
        base_ins,
        ("BAD_PRICE", d_id, p_id, co_id, ch_id, pm_id, il_id, 8, -50, 10, 1, 4.0),
        CheckViolation,
    )
    must_fail(
        "non-existent country_id rejected (FK)",
        base_ins,
        ("BAD_FK", d_id, p_id, 9999, ch_id, pm_id, il_id, 8, 100, 10, 1, 4.0),
        ForeignKeyViolation,
    )

    # -----------------------------------------------------------
    section("3. View correctness vs pandas recomputation")
    # -----------------------------------------------------------
    df = pd.read_csv(CSV_PATH)
    df["final_price"] = df["base_price_usd"] * (1 - df["discount_percent"] / 100)
    df["revenue"] = df["final_price"] * df["units_sold"]

    def tier(p):
        if p == 0: return "0%"
        if p <= 10: return "1-10%"
        if p <= 20: return "11-20%"
        if p <= 30: return "21-30%"
        return "30%+"

    df["tier"] = df["discount_percent"].apply(tier)
    pd_agg = df.groupby("tier")["revenue"].sum().round(2).to_dict()

    cur.execute("SELECT discount_tier, total_revenue FROM v_discount_tier_revenue")
    db_agg = {t: float(r) for t, r in cur.fetchall()}

    for t in pd_agg:
        pd_val = round(pd_agg[t], 2)
        db_val = db_agg.get(t, 0)
        check(f"discount_tier '{t}' total_revenue matches",
              abs(pd_val - db_val) < 0.05,
              f"pandas={pd_val:.2f} db={db_val:.2f}")

    # Cross-check country totals
    pd_country = df.groupby("country")["revenue"].sum().round(2).to_dict()
    cur.execute("SELECT country_name, total_revenue FROM v_geography_demand")
    db_country = {c: float(r) for c, r in cur.fetchall()}
    for c in pd_country:
        pd_val = round(pd_country[c], 2)
        db_val = db_country.get(c, 0)
        check(f"country '{c}' total_revenue matches",
              abs(pd_val - db_val) < 0.05,
              f"pandas={pd_val:.2f} db={db_val:.2f}")

    # -----------------------------------------------------------
    section("4. Normalization smell-test")
    # -----------------------------------------------------------
    # Brand/category/etc. names should only live in their dim tables —
    # not as string columns in Orders or Products.
    cur.execute("""
        SELECT c.column_name, c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables  t
          ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE c.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'      -- exclude views
          AND c.data_type IN ('character varying','text')
          AND c.column_name IN ('brand_name','category_name','country_name',
                              'channel_name','method_name','level_name','gender_name')
        ORDER BY c.table_name, c.column_name
    """)
    rows = cur.fetchall()
    offenders = [(c, t) for c, t in rows if t not in (
        "brands","categories","countries","channels",
        "paymentmethods","incomelevels","genders"
    )]
    check("no denormalized name columns outside dim tables",
          len(offenders) == 0, f"offenders={offenders}")

    # -----------------------------------------------------------
    section("5. Role enforcement (smoke)")
    # -----------------------------------------------------------
    try:
        pcur = psycopg2.connect(
            dbname="footwear_analytics", user="analyst_pricing",
            password="pricing_pw", host="localhost", port="5432"
        ).cursor()
        # Should succeed
        pcur.execute("SELECT 1 FROM v_discount_tier_revenue LIMIT 1")
        check("analyst_pricing CAN read v_discount_tier_revenue", True)
        # Should fail
        try:
            pcur.execute("SELECT 1 FROM orders LIMIT 1")
            check("analyst_pricing BLOCKED from orders", False, "unexpectedly allowed")
        except psycopg2.errors.InsufficientPrivilege:
            check("analyst_pricing BLOCKED from orders", True)
    except Exception as e:
        check("role smoke test", False, str(e))

    # -----------------------------------------------------------
    print(f"\n=== Summary ===")
    print(f"  PASS: {PASS}")
    print(f"  FAIL: {FAIL}")
    cur.close()
    conn.close()
    sys.exit(0 if FAIL == 0 else 1)


if __name__ == "__main__":
    main()
