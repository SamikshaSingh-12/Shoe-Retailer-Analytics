-- ============================================================
-- Sample Analytics Queries
-- One runnable query per question. Each uses the views so the
-- business logic (discount tiers, revenue formula) stays in
-- views.sql and these stay short.
--
-- Run individually or as a batch:
--   psql -d footwear_analytics -f queries.sql
-- ============================================================


-- ============================================================
-- PROBLEM 1: PRICING STRATEGY
-- ============================================================

-- Q1. Discount Depth vs Revenue Yield
-- Where does deeper discounting stop generating incremental revenue?
\echo '--- Q1: Discount tier revenue ---'
SELECT *
FROM v_discount_tier_revenue;


-- Q2. Brand-Level Price Sensitivity
-- Which brands hold revenue at full price vs need discounts?
-- Pivot the view: one row per brand, columns per tier.
\echo '--- Q2: Brand price sensitivity (revenue by tier, per brand) ---'
SELECT
    brand_name,
    SUM(total_revenue) FILTER (WHERE discount_tier = '0%')     AS rev_0pct,
    SUM(total_revenue) FILTER (WHERE discount_tier = '1-10%')  AS rev_1_10,
    SUM(total_revenue) FILTER (WHERE discount_tier = '11-20%') AS rev_11_20,
    SUM(total_revenue) FILTER (WHERE discount_tier = '21-30%') AS rev_21_30,
    SUM(total_revenue)                                         AS total_rev
FROM v_brand_price_sensitivity
GROUP BY brand_name
ORDER BY total_rev DESC;


-- Q3. Category-Level Discount Effectiveness
-- Which categories should we discount aggressively vs hold at price?
-- Rule of thumb: if avg-revenue-per-order drops sharply with discount,
-- the category is discount-hostile (don't promote); if it holds, promote.
\echo '--- Q3: Category x tier avg revenue per order ---'
SELECT
    category_name,
    discount_tier,
    order_count,
    avg_revenue_per_order,
    avg_rating
FROM v_category_discount_effectiveness
ORDER BY category_name, discount_tier;


-- Q4. Channel-Specific Pricing Behavior
-- Online vs Retail Store: where does discounting actually lift revenue?
\echo '--- Q4: Channel pricing behavior ---'
SELECT
    channel_name,
    discount_tier,
    order_count,
    avg_discount_pct,
    avg_revenue_per_order,
    total_revenue
FROM v_channel_pricing_behavior
ORDER BY channel_name, discount_tier;


-- ============================================================
-- PROBLEM 2: CUSTOMER BEHAVIOR & PRODUCT PREFERENCES
-- ============================================================

-- Q5. Satisfaction Drivers by Product Attribute
-- Top 10 (brand, category, gender, price-band) combos by avg rating.
-- Informs assortment planning: stock more of what rates highest.
\echo '--- Q5: Top 10 combos by avg rating ---'
SELECT
    brand_name,
    category_name,
    gender_name,
    price_band,
    order_count,
    avg_rating,
    total_revenue
FROM v_satisfaction_drivers
ORDER BY avg_rating DESC, total_revenue DESC
LIMIT 10;


-- Q6. Geography & Demand Concentration
-- Rank countries; shows income mix (which segments each market serves).
\echo '--- Q6: Country ranking by revenue, with income mix ---'
SELECT *
FROM v_geography_demand;


-- Q7. Size & Color Demand (inventory assortment)
-- Top 10 (size, color) SKUs per country for the Running category.
\echo '--- Q7: Top Running size+color by country ---'
SELECT
    country_name,
    size,
    color,
    total_units,
    total_revenue
FROM v_size_color_demand
WHERE category_name = 'Running'
ORDER BY country_name, total_units DESC
LIMIT 30;


-- Q8. Temporal Trends — YoY revenue growth by category
\echo '--- Q8a: YoY revenue by category ---'
SELECT
    year,
    category_name,
    SUM(total_revenue) AS revenue
FROM v_temporal_trends
GROUP BY year, category_name
ORDER BY category_name, year;

-- Q8b. Monthly seasonality across all years
\echo '--- Q8b: Monthly seasonality (all years aggregated) ---'
SELECT
    month,
    month_name,
    category_name,
    SUM(total_revenue) AS revenue
FROM v_temporal_trends
GROUP BY month, month_name, category_name
ORDER BY category_name, month;


-- ============================================================
-- BONUS
-- ============================================================

-- Q9. Rating vs Discount (clearance effect vs value perception)
\echo '--- Q9: Rating vs discount tier ---'
SELECT *
FROM v_rating_vs_discount;
