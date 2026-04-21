-- ============================================================
-- Role-Based Access Control
-- Enforces the ethics-section claim that pricing analysts must
-- not see customer demographic fields (income_level, rating).
-- ============================================================
-- Usage (as a superuser):
--   psql -d footwear_analytics -f roles.sql
-- ============================================================

-- Clean slate (safe re-run)
DROP OWNED BY analyst_pricing  CASCADE;
DROP OWNED BY analyst_behavior CASCADE;
DROP ROLE IF EXISTS analyst_pricing;
DROP ROLE IF EXISTS analyst_behavior;


-- ============================================================
-- 1. Create roles (LOGIN so they can be tested via psql -U)
-- ============================================================
CREATE ROLE analyst_pricing  LOGIN PASSWORD 'pricing_pw';
CREATE ROLE analyst_behavior LOGIN PASSWORD 'behavior_pw';


-- ============================================================
-- 2. Pricing analyst
-- Can see: pricing/product/channel/time.
-- CANNOT see: income_level, customer_rating (neither on Orders
-- nor via behavior views).
-- ============================================================
GRANT CONNECT ON DATABASE footwear_analytics TO analyst_pricing;
GRANT USAGE   ON SCHEMA public               TO analyst_pricing;

-- Dimension tables they can read freely (no PII)
GRANT SELECT ON Brands, Categories, Genders, Channels, Countries,
                PaymentMethods, DateDim, Products
            TO analyst_pricing;

-- Pricing views only
GRANT SELECT ON v_discount_tier_revenue,
                v_brand_price_sensitivity,
                v_category_discount_effectiveness,
                v_channel_pricing_behavior
            TO analyst_pricing;

-- Explicitly NOT granted:
--   * Orders (contains income_level_id, customer_rating)
--   * IncomeLevels
--   * v_orders_enriched (exposes both sensitive fields)
--   * v_satisfaction_drivers, v_geography_demand, v_rating_vs_discount
--     (all expose rating, income, or both)


-- ============================================================
-- 3. Behavior analyst
-- Can see: aggregated behavioral metrics (ratings, income mix).
-- CANNOT see: raw per-order rows, individual ratings, or raw
-- pricing history (only aggregated pricing exposure).
-- ============================================================
GRANT CONNECT ON DATABASE footwear_analytics TO analyst_behavior;
GRANT USAGE   ON SCHEMA public               TO analyst_behavior;

-- Dimension tables (needed to interpret the views)
GRANT SELECT ON Brands, Categories, Genders, Channels, Countries,
                IncomeLevels, DateDim, Products
            TO analyst_behavior;

-- Behavior views (already aggregated — no individual rows leak)
GRANT SELECT ON v_satisfaction_drivers,
                v_geography_demand,
                v_size_color_demand,
                v_temporal_trends,
                v_rating_vs_discount
            TO analyst_behavior;

-- Explicitly NOT granted:
--   * Orders           (raw transactions, includes rating per order)
--   * PaymentMethods   (not relevant; keep scope minimal)
--   * v_orders_enriched (row-level leakage)
--   * Pricing views    (not in scope)


-- ============================================================
-- 4. Default privileges — protect future objects too.
-- Without this, any NEW table/view created later would be
-- implicitly accessible only by the owner, but we want to make
-- sure the roles never auto-inherit access to new objects.
-- ============================================================
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE ALL ON TABLES FROM analyst_pricing, analyst_behavior;


-- ============================================================
-- 5. Verification block
-- Run these manually (or see queries.sql) to confirm isolation:
--
--   -- Should succeed:
--   psql -U analyst_pricing  -d footwear_analytics \
--        -c "SELECT * FROM v_discount_tier_revenue LIMIT 3;"
--
--   -- Should FAIL with "permission denied for table orders":
--   psql -U analyst_pricing  -d footwear_analytics \
--        -c "SELECT customer_rating FROM orders LIMIT 1;"
--
--   -- Should FAIL with "permission denied for view v_satisfaction_drivers":
--   psql -U analyst_pricing  -d footwear_analytics \
--        -c "SELECT * FROM v_satisfaction_drivers LIMIT 1;"
--
--   -- Should succeed:
--   psql -U analyst_behavior -d footwear_analytics \
--        -c "SELECT * FROM v_geography_demand LIMIT 3;"
--
--   -- Should FAIL (raw Orders blocked for behavior role too):
--   psql -U analyst_behavior -d footwear_analytics \
--        -c "SELECT * FROM orders LIMIT 1;"
-- ============================================================
