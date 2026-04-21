-- ============================================================
-- Analytic Views
-- One view per analytics question (9 total: 4 pricing + 4 behavior + 1 bonus)
-- ============================================================
-- Usage:
--   psql -d footwear_analytics -f views.sql
-- ============================================================

-- Drop in reverse-dependency order (views depend on v_orders_enriched)
DROP VIEW IF EXISTS v_rating_vs_discount              CASCADE;
DROP VIEW IF EXISTS v_temporal_trends                 CASCADE;
DROP VIEW IF EXISTS v_size_color_demand               CASCADE;
DROP VIEW IF EXISTS v_geography_demand                CASCADE;
DROP VIEW IF EXISTS v_satisfaction_drivers            CASCADE;
DROP VIEW IF EXISTS v_channel_pricing_behavior        CASCADE;
DROP VIEW IF EXISTS v_category_discount_effectiveness CASCADE;
DROP VIEW IF EXISTS v_brand_price_sensitivity         CASCADE;
DROP VIEW IF EXISTS v_discount_tier_revenue           CASCADE;
DROP VIEW IF EXISTS v_orders_enriched                 CASCADE;


-- ============================================================
-- Base view: orders joined with dimensions + derived metrics.
-- All other views read from this so the discount-tier logic and
-- revenue formula live in exactly one place.
-- ============================================================
CREATE VIEW v_orders_enriched AS
SELECT
    o.order_id,
    d.full_date,
    d.year,
    d.quarter,
    d.month,
    d.month_name,
    d.is_weekend,
    b.brand_name,
    cat.category_name,
    g.gender_name,
    ch.channel_name,
    co.country_name,
    pm.method_name                 AS payment_method,
    il.level_name                  AS income_level,
    o.size,
    o.color,
    o.base_price_usd,
    o.discount_percent,
    o.units_sold,
    o.customer_rating,
    -- Derived
    ROUND(o.base_price_usd * (1 - o.discount_percent/100.0), 2)              AS final_price_usd,
    ROUND(o.base_price_usd * (1 - o.discount_percent/100.0) * o.units_sold, 2) AS revenue_usd,
    CASE
        WHEN o.discount_percent = 0               THEN '0%'
        WHEN o.discount_percent BETWEEN  1 AND 10 THEN '1-10%'
        WHEN o.discount_percent BETWEEN 11 AND 20 THEN '11-20%'
        WHEN o.discount_percent BETWEEN 21 AND 30 THEN '21-30%'
        ELSE '30%+'
    END AS discount_tier,
    CASE
        WHEN o.base_price_usd < 75  THEN 'Budget (<$75)'
        WHEN o.base_price_usd < 150 THEN 'Mid ($75-150)'
        ELSE 'Premium ($150+)'
    END AS price_band
FROM Orders o
JOIN DateDim        d   ON d.date_id           = o.date_id
JOIN Products       p   ON p.product_id        = o.product_id
JOIN Brands         b   ON b.brand_id          = p.brand_id
JOIN Categories     cat ON cat.category_id     = p.category_id
JOIN Genders        g   ON g.gender_id         = p.gender_id
JOIN Channels       ch  ON ch.channel_id       = o.channel_id
JOIN Countries      co  ON co.country_id       = o.country_id
JOIN PaymentMethods pm  ON pm.payment_method_id= o.payment_method_id
JOIN IncomeLevels   il  ON il.income_level_id  = o.income_level_id;


-- ============================================================
-- PRICING ANALYTICS (Problem 1)
-- ============================================================

-- Q1: Discount Depth vs. Revenue Yield
-- Does deeper discounting drive more total revenue, or erode margin?
CREATE VIEW v_discount_tier_revenue AS
SELECT
    discount_tier,
    COUNT(*)                          AS order_count,
    SUM(units_sold)                   AS total_units,
    ROUND(AVG(revenue_usd)::numeric, 2) AS avg_revenue_per_order,
    ROUND(SUM(revenue_usd)::numeric, 2) AS total_revenue,
    ROUND(AVG(customer_rating)::numeric, 2) AS avg_rating
FROM v_orders_enriched
GROUP BY discount_tier
ORDER BY
    CASE discount_tier
        WHEN '0%' THEN 1 WHEN '1-10%' THEN 2 WHEN '11-20%' THEN 3
        WHEN '21-30%' THEN 4 WHEN '30%+' THEN 5
    END;


-- Q2: Brand-Level Price Sensitivity
-- Which brands hold volume at full price vs which need discounts?
CREATE VIEW v_brand_price_sensitivity AS
SELECT
    brand_name,
    discount_tier,
    COUNT(*)                           AS order_count,
    SUM(units_sold)                    AS total_units,
    ROUND(SUM(revenue_usd)::numeric, 2) AS total_revenue,
    ROUND(AVG(revenue_usd)::numeric, 2) AS avg_revenue_per_order
FROM v_orders_enriched
GROUP BY brand_name, discount_tier
ORDER BY brand_name,
    CASE discount_tier
        WHEN '0%' THEN 1 WHEN '1-10%' THEN 2 WHEN '11-20%' THEN 3
        WHEN '21-30%' THEN 4 WHEN '30%+' THEN 5
    END;


-- Q3: Category-Level Discount Effectiveness
-- Which categories to discount aggressively vs hold at full price?
CREATE VIEW v_category_discount_effectiveness AS
SELECT
    category_name,
    discount_tier,
    COUNT(*)                           AS order_count,
    SUM(units_sold)                    AS total_units,
    ROUND(SUM(revenue_usd)::numeric, 2) AS total_revenue,
    ROUND(AVG(revenue_usd)::numeric, 2) AS avg_revenue_per_order,
    ROUND(AVG(customer_rating)::numeric, 2) AS avg_rating
FROM v_orders_enriched
GROUP BY category_name, discount_tier
ORDER BY category_name,
    CASE discount_tier
        WHEN '0%' THEN 1 WHEN '1-10%' THEN 2 WHEN '11-20%' THEN 3
        WHEN '21-30%' THEN 4 WHEN '30%+' THEN 5
    END;


-- Q4: Channel-Specific Pricing Behavior
-- Should promotional pricing concentrate Online or spread across both?
CREATE VIEW v_channel_pricing_behavior AS
SELECT
    channel_name,
    discount_tier,
    COUNT(*)                               AS order_count,
    ROUND(AVG(discount_percent)::numeric, 2) AS avg_discount_pct,
    ROUND(SUM(revenue_usd)::numeric, 2)     AS total_revenue,
    ROUND(AVG(revenue_usd)::numeric, 2)     AS avg_revenue_per_order,
    ROUND(AVG(customer_rating)::numeric, 2) AS avg_rating
FROM v_orders_enriched
GROUP BY channel_name, discount_tier
ORDER BY channel_name,
    CASE discount_tier
        WHEN '0%' THEN 1 WHEN '1-10%' THEN 2 WHEN '11-20%' THEN 3
        WHEN '21-30%' THEN 4 WHEN '30%+' THEN 5
    END;


-- ============================================================
-- BEHAVIOR ANALYTICS (Problem 2, refreshed)
-- ============================================================

-- Q5: Satisfaction Drivers by Product Attribute
-- Which (brand, category, gender, price-band) combos produce rating >= 4.5?
CREATE VIEW v_satisfaction_drivers AS
SELECT
    brand_name,
    category_name,
    gender_name,
    price_band,
    discount_tier,
    COUNT(*)                                AS order_count,
    ROUND(AVG(customer_rating)::numeric, 2) AS avg_rating,
    ROUND(SUM(revenue_usd)::numeric, 2)     AS total_revenue,
    (AVG(customer_rating) >= 4.5)           AS is_high_satisfaction
FROM v_orders_enriched
GROUP BY brand_name, category_name, gender_name, price_band, discount_tier
HAVING COUNT(*) >= 10   -- avoid noise from tiny slices
ORDER BY avg_rating DESC;


-- Q6: Geography & Demand Concentration
-- Rank countries by revenue/volume/satisfaction + income-mix.
CREATE VIEW v_geography_demand AS
SELECT
    country_name,
    COUNT(*)                                         AS order_count,
    SUM(units_sold)                                  AS total_units,
    ROUND(SUM(revenue_usd)::numeric, 2)              AS total_revenue,
    ROUND(AVG(revenue_usd)::numeric, 2)              AS avg_revenue_per_order,
    ROUND(AVG(customer_rating)::numeric, 2)          AS avg_rating,
    ROUND(100.0 * SUM(CASE WHEN income_level = 'Low'    THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_low,
    ROUND(100.0 * SUM(CASE WHEN income_level = 'Medium' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_medium,
    ROUND(100.0 * SUM(CASE WHEN income_level = 'High'   THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_high
FROM v_orders_enriched
GROUP BY country_name
ORDER BY total_revenue DESC;


-- Q7: Size & Color Demand Curves (for inventory assortment)
CREATE VIEW v_size_color_demand AS
SELECT
    country_name,
    category_name,
    size,
    color,
    COUNT(*)                            AS order_count,
    SUM(units_sold)                     AS total_units,
    ROUND(SUM(revenue_usd)::numeric, 2) AS total_revenue
FROM v_orders_enriched
GROUP BY country_name, category_name, size, color
ORDER BY country_name, category_name, total_units DESC;


-- Q8: Temporal Trends (YoY + monthly seasonality by category and country)
CREATE VIEW v_temporal_trends AS
SELECT
    year,
    month,
    month_name,
    category_name,
    country_name,
    COUNT(*)                            AS order_count,
    SUM(units_sold)                     AS total_units,
    ROUND(SUM(revenue_usd)::numeric, 2) AS total_revenue,
    ROUND(AVG(customer_rating)::numeric, 2) AS avg_rating
FROM v_orders_enriched
GROUP BY year, month, month_name, category_name, country_name
ORDER BY year, month, category_name, country_name;


-- Q9 (bonus): Rating vs Discount (clearance-effect vs value-perception)
CREATE VIEW v_rating_vs_discount AS
SELECT
    discount_tier,
    COUNT(*)                                AS order_count,
    ROUND(AVG(customer_rating)::numeric, 2) AS avg_rating,
    ROUND(STDDEV(customer_rating)::numeric, 2) AS rating_stddev,
    ROUND(AVG(revenue_usd)::numeric, 2)     AS avg_revenue_per_order
FROM v_orders_enriched
GROUP BY discount_tier
ORDER BY
    CASE discount_tier
        WHEN '0%' THEN 1 WHEN '1-10%' THEN 2 WHEN '11-20%' THEN 3
        WHEN '21-30%' THEN 4 WHEN '30%+' THEN 5
    END;
