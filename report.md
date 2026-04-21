# Global Sports Footwear — Retailer Analytics Database

**Final Project Report — ILS-Z 511 Database Design**

**Group Members:** Samiksha Singh, Dhruvil Joshi, Sudha Swain, Abhijeet Thorat

---

## Executive Summary

This project designs, implements, and verifies a normalised relational database that transforms a flat commercial-sales CSV into an analytics-ready foundation for global sports-footwear retailers. Starting from a 30,000-row, 18-column Kaggle dataset covering six brands, six countries, and nine years (2018–2026), we produced a ten-table PostgreSQL schema in third normal form, populated it via an idempotent Python ETL, layered nine analytic views on top, enforced role-based access control in SQL, and verified the end-to-end pipeline with a 27-check automated test suite — all of which pass.

The resulting database answers eight retailer-relevant questions spanning pricing strategy and customer-behaviour analysis, using only aggregate-level SQL. The access-control layer operationalises the ethics mitigations promised in the intermediate proposal: pricing analysts are physically prevented by the database engine from reading demographic columns, not merely asked not to. The schema is designed for a future web-application front end, but every question is already answerable today by a short SQL query against a view.

---

## 1. Community / Population

The project focuses on **sports-footwear retailers operating in the global marketplace** — regional and multi-brand retail chains, independent sports-goods stores, and online footwear platforms that make continuous, data-driven decisions about pricing, product assortment, and inventory allocation across diverse markets.

### 1.1 Defining the Community

Retailers — rather than consumers or brand manufacturers — are the primary community of interest because they sit at the decision boundary where pricing, assortment, and channel strategy are actually executed. Brands set wholesale prices and authorised discount ceilings; retailers decide the in-store and online promotional depth, manage inventory assortment across categories (Running, Training, Basketball, Lifestyle, Gym), and choose which customer segments to target in each market.

The dataset we use captures outcomes from both perspectives in a single transactional record — the base price set by the brand, the final price after the retailer's discount, the channel used, the units moved, and the customer-satisfaction outcome — making it possible to analyse the full pricing-to-purchase chain in one place.

### 1.2 Why Retailers

Three considerations drove the choice of retailers as the focal community:

- **Data alignment.** Every row in the dataset records a sale from the seller's perspective: the price set, the discount applied, the channel used, the revenue generated, and the units moved. This is the vocabulary of retail and brand operations, not consumer journeys.
- **Decision-making authority.** Both problem statements in this report — pricing strategy and customer-behaviour profiling — are actionable only by organisations with the power to change prices and stock decisions. Retailers hold that authority; individual consumers do not.
- **Commercial scale.** The dataset spans six major global brands, six countries, and nine years. This mirrors the multi-market reporting environment retail buyers actually operate in, making the analysis realistic and transferable.

---

## 2. Dataset & Source

### 2.1 Overview

The dataset used is the **Global Sports Footwear Sales & Consumer Behaviour Dataset**, publicly available on Kaggle.

- **Source:** [https://www.kaggle.com/datasets/aliiihussain/sports-footwear-sales-and-consumer-behavior/data](https://www.kaggle.com/datasets/aliiihussain/sports-footwear-sales-and-consumer-behavior/data)
- **Published by:** Alii Hussain (Kaggle contributor)
- **Licence:** Open Data — publicly accessible for educational and research use

The dataset was selected because its 18 attributes map directly onto the decision variables that brands and retailers use day-to-day, and because it provides all the attributes needed to populate a normalised relational schema without external augmentation.

### 2.2 Dataset Characteristics

The dataset is a realistic simulation of global sports-footwear sales transactions. It contains no personally identifiable consumer data.


| Property          | Detail                                                  |
| ----------------- | ------------------------------------------------------- |
| Total records     | 30,000 rows                                             |
| Total attributes  | 18 columns                                              |
| Time period       | 31 Dec 2017 — 30 Dec 2026                               |
| Mean transaction  | 28 Jun 2022                                             |
| Brands covered    | 6 (Nike, Adidas, Puma, Reebok, ASICS, New Balance)      |
| Countries covered | 6 (UAE, UK, USA, India, Germany, Pakistan)              |
| Data quality      | 100% valid across all columns — 0 missing, 0 mismatched |


### 2.3 Attribute Description


| Attribute               | Description                                   |
| ----------------------- | --------------------------------------------- |
| `order_id`              | Unique ID per sale                            |
| `order_date`            | Date of the sale                              |
| `brand`                 | Brand of the shoe                             |
| `model_name`            | Specific model of the shoe                    |
| `category`              | Running, Training, Basketball, Lifestyle, Gym |
| `gender`                | Men, Women, Unisex                            |
| `size`                  | Shoe size (integer, 6–11)                     |
| `color`                 | Shoe colour                                   |
| `base_price_usd`        | Original price                                |
| `discount_percent`      | Discount applied (0–30%)                      |
| `final_price_usd`       | Price after discount                          |
| `units_sold`            | Quantity sold                                 |
| `revenue_usd`           | Total revenue for the order                   |
| `payment_method`        | Card, Cash, Wallet, Bank Transfer             |
| `sales_channel`         | Online / Retail Store                         |
| `country`               | Country of sale                               |
| `customer_income_level` | Low / Medium / High                           |
| `customer_rating`       | Satisfaction score 3.0–5.0                    |


### 2.4 Data-Shape Findings That Informed Design

Profiling the CSV before schema design surfaced two facts that changed the design materially:

1. `**model_name` alone does not identify a product.** The same `(brand, model_name)` pair — for example, *Adidas Model-100* — appears with different `category`, `gender`, and `base_price_usd` values (from $71 to $216) across rows. There are 5,369 distinct `(brand, model)` pairs but 29,448 distinct `(brand, model, base_price)` combinations. A product SKU must be keyed on `(brand, model, category, gender)`, and `base_price` must be treated as a per-transaction attribute rather than a product attribute.
2. **There is no customer identifier.** `customer_income_level` and `customer_rating` are per-order snapshots. Two orders from the same "customer" are not linkable. Any design that introduces a `Customer` entity would be fabricating data, and any question requiring customer identity (e.g., loyalty, lifetime value) cannot honestly be answered.

Both findings are addressed in the final design described in §4.

---

## 3. Problems & Analytics Questions

### 3.1 Why These Two Problem Areas

The eighteen CSV attributes map precisely onto the decision variables retailers use day-to-day. Pairing `base_price` with `final_price` and `revenue` yields pricing intelligence; pairing `customer_income_level` and `country` with `customer_rating` yields behavioural intelligence. No single attribute answers a retailer question in isolation — it is the *relational combination* that produces actionable insight, which is precisely the motivation for migrating the flat dataset into a normalised relational database.

Two problem areas emerged as the highest-value operational challenges the data can support:

1. **Pricing strategy.** Pricing is the single most frequent and highest-stakes decision in retail operations. The dataset contains both the input variable (`discount_percent`) and the output metrics (`units_sold`, `revenue_usd`), allowing us to empirically test discount effectiveness rather than relying on intuition.
2. **Customer behaviour (at the segment level).** Retailers invest heavily in stocking decisions with limited visibility into which product combinations actually produce satisfied customers. The `customer_rating` column, analysed alongside product attributes and demographic proxies, provides that visibility.

Both problems are answerable at the aggregate level using transactional data, without requiring personally identifiable information — making them ethically appropriate for analysis.

### 3.2 The Eight Analytics Questions

These were refined from the intermediate proposal. The earlier "Customer Loyalty" question was dropped because the dataset has no customer identifier (see §2.4); the earlier "Payment Method as a Behavioural Signal" question was replaced with a stronger inventory-oriented question, and two new questions (temporal trends, and rating-vs-discount interaction) were added to exploit the 9-year span and to explicitly connect the two problem areas.

#### Problem 1 — Pricing Strategy

- **Q1. Discount Depth vs. Revenue Yield.** Group orders into discount tiers (0%, 1–10%, 11–20%, 21–30%, 30%+) and compare order count, units, and revenue per tier to identify the inflection point where deeper discounts stop generating incremental revenue.
- **Q2. Brand-Level Price Sensitivity.** Measure each brand's volume response across discount levels to determine which brands are discount-dependent and which hold volume at full price — informing promotional selection and brand-partner negotiation.
- **Q3. Category-Level Discount Effectiveness.** Build a category × discount-tier matrix of revenue, units, and average rating to produce a pricing playbook: which categories to discount aggressively, hold at price, or promote to clear inventory.
- **Q4. Channel-Specific Pricing Behaviour.** Compare discount distributions and revenue outcomes between Online and Retail Store channels to determine whether promotional pricing should be concentrated digitally or spread across both.

#### Problem 2 — Customer Behaviour & Product Preferences

- **Q5. Satisfaction Drivers by Product Attribute.** Rank (brand, category, gender, price-band, discount-tier) combinations by average rating to identify which attribute combinations consistently produce satisfied customers and should be prioritised in assortment planning.
- **Q6. Geography & Demand Concentration.** Rank countries by revenue, units, and average rating, overlaid with income-level distribution, to surface commercially valuable markets and identify regions with unmet demand or satisfaction gaps.
- **Q7. Size & Colour Demand Curves.** Break `units_sold` down by (country, category, size, colour) to directly inform inventory assortment and country-specific stocking decisions — a dimension under-utilised in the original proposal.
- **Q8. Temporal Trends.** Compute year-over-year revenue growth by category × country and monthly seasonality by category, using the nine-year span that would otherwise go unused.

#### Bonus

- **Q9. Rating vs. Discount Interaction.** Does heavy discounting correlate with lower ratings (clearance effect) or higher ratings (value perception)? Connects Problem 1 and Problem 2 directly.

---

## 4. Database Design

### 4.1 Design Goals

The schema was designed to satisfy four properties simultaneously:

1. **Third normal form** — no transitive dependencies, no repeating groups, every non-key attribute depends on the whole key.
2. **Referential integrity** — every foreign key enforced by the database, every enumerated domain enforced by a check constraint or lookup table.
3. **Analytics-ready** — aggregations over millions of rows possible through indexed foreign keys and pre-joined views.
4. **Privacy-enforceable** — sensitive columns isolated so that role-based access control (§6) can restrict them without touching application code.

### 4.2 Entity-Relationship Diagram

The final ER diagram (rendered from `er_diagram.mmd`) is shown in Figure 1. It differs from the intermediate proposal in three ways:

- The `Customers` entity is removed (data cannot support it — see §2.4).
- The `Discounts` entity is removed (its attributes were per-order and are now on `Orders`; `final_price` is derived, not stored).
- The `Products` entity is re-keyed on `(brand_id, model_name, category_id, gender_id)` and no longer carries `base_price`, `size`, or `color` — all three vary per transaction in the source data and would create update anomalies if modelled as product attributes.

**Figure 1 — ER diagram.** (Rendered from `er_diagram.mmd` in Mermaid.)

ER diagram

### 4.3 Schema — Table Summary

The database comprises **ten tables**: eight dimension / lookup tables, one product table, and one transactional fact table.

#### Dimension tables


| Table            | Key                  | Purpose                                         | Row count |
| ---------------- | -------------------- | ----------------------------------------------- | --------- |
| `Brands`         | `brand_id`           | 6 global brands                                 | 6         |
| `Categories`     | `category_id`        | 5 product categories                            | 5         |
| `Genders`        | `gender_id`          | Men / Women / Unisex                            | 3         |
| `Channels`       | `channel_id`         | Online / Retail Store                           | 2         |
| `Countries`      | `country_id`         | 6 countries of sale                             | 6         |
| `PaymentMethods` | `payment_method_id`  | 4 payment methods                               | 4         |
| `IncomeLevels`   | `income_level_id`    | Low / Medium / High (restricted-access in §6)   | 3         |
| `DateDim`        | `date_id` (YYYYMMDD) | Date dimension: year, quarter, month, week, dow | 3,287     |


#### Core entities


| Table      | Key                                                          | Cardinality        | Row count |
| ---------- | ------------------------------------------------------------ | ------------------ | --------- |
| `Products` | `product_id`; UNIQUE `(brand, model_name, category, gender)` | —                  | 25,055    |
| `Orders`   | `order_id`                                                   | transactional fact | 30,000    |


The `Orders` table carries all per-transaction attributes: `size`, `color`, `base_price_usd`, `discount_percent`, `units_sold`, `customer_rating`, plus foreign keys into every dimension. `final_price_usd` and `revenue_usd` are **not stored** — they are derived in the `v_orders_enriched` view to avoid update anomalies (classic 3NF motivation).

### 4.4 Normalisation Evidence

- **1NF:** Every column is atomic; there are no list-valued or multi-valued attributes.
- **2NF:** `Orders` has a single-attribute primary key (`order_id`), so there are no partial-key dependencies to eliminate.
- **3NF:** Non-key attributes on `Orders` depend only on `order_id`. Brand name is not stored on `Orders` — it is stored once in `Brands` and reached via `Products → Brands`. The same holds for every other enumerated domain. The automated normalisation smell-test (§7) confirms that no denormalised name column (e.g., `brand_name`, `country_name`) appears on any base table outside its dimension.

### 4.5 Integrity Constraints

Integrity is enforced at the database level, not at the application level, so that future applications cannot accidentally insert bad data.

- **Foreign-key constraints** — every `*_id` column in `Orders` and `Products` references the corresponding dimension's primary key.
- **Check constraints** on `Orders`:
  - `discount_percent BETWEEN 0 AND 100`
  - `units_sold > 0`
  - `customer_rating BETWEEN 3.0 AND 5.0`
  - `base_price_usd > 0`
  - `size BETWEEN 1 AND 20`
- **Domain check constraints** on dimension tables — e.g., `Genders.gender_name IN ('Men','Women','Unisex')` — as a second layer guaranteeing the dimension tables themselves never drift.
- **UNIQUE constraint** on `(brand_id, model_name, category_id, gender_id)` in `Products` — prevents duplicate product entries.

§7 demonstrates that each of these constraints actively rejects invalid data.

### 4.6 Indexing

Every foreign key on `Orders` has a B-tree index (`idx_orders_date`, `idx_orders_product`, `idx_orders_country`, `idx_orders_channel`, `idx_orders_income`, `idx_orders_payment`). This supports the analytic views, which all join `Orders` to its dimensions.

### 4.7 ETL Pipeline

A Python script (`etl.py`) implements a clean, idempotent load:

1. Read the CSV with `pandas`.
2. Truncate all tables with `RESTART IDENTITY CASCADE` (safe re-run).
3. Derive lookup tables from the distinct values of each categorical column.
4. Pre-populate `DateDim` for the full date span (3,287 days).
5. Derive `Products` from the distinct `(brand, model, category, gender)` tuples.
6. Insert 30,000 rows into `Orders` with foreign keys resolved via in-memory lookup maps.

The entire ETL runs in under 10 seconds on a local machine and leaves the database in a known, verified state (§7).

---

## 5. How the Database Answers the Questions

### 5.1 Architecture

A **base view** (`v_orders_enriched`) joins `Orders` to every dimension and computes derived fields (`final_price_usd`, `revenue_usd`, `discount_tier`, `price_band`) in exactly one place. The nine question-specific views read from this base view, so the revenue formula and discount-tier boundaries never drift across queries.

```
Orders (fact) + 8 dimensions
      │
      ▼
v_orders_enriched  (base: joins + derived fields)
      │
      ▼
9 analytic views — one per question
      │
      ▼
queries.sql  —  short queries for the report / web-app / BI tool
```

### 5.2 View-to-Question Mapping


| #   | Question                              | View(s)                             |
| --- | ------------------------------------- | ----------------------------------- |
| 1   | Discount depth vs revenue yield       | `v_discount_tier_revenue`           |
| 2   | Brand-level price sensitivity         | `v_brand_price_sensitivity`         |
| 3   | Category-level discount effectiveness | `v_category_discount_effectiveness` |
| 4   | Channel-specific pricing              | `v_channel_pricing_behavior`        |
| 5   | Satisfaction drivers                  | `v_satisfaction_drivers`            |
| 6   | Geography & demand concentration      | `v_geography_demand`                |
| 7   | Size & colour demand                  | `v_size_color_demand`               |
| 8   | Temporal trends                       | `v_temporal_trends`                 |
| 9   | Rating vs discount (bonus)            | `v_rating_vs_discount`              |


Every question is answered by **one** `SELECT` against its view — visible in full in `queries.sql`.

### 5.3 Sample Outputs

The following outputs are reproduced verbatim from the running database.

#### Q1 — Discount Depth vs. Revenue Yield


| discount_tier | order_count | total_units | avg_rev/order | total_revenue | avg_rating |
| ------------- | ----------- | ----------- | ------------- | ------------- | ---------- |
| 0%            | 4,971       | 12,366      | $346.77       | $1,723,813.00 | 3.99       |
| 1–10%         | 10,063      | 25,175      | $323.99       | $3,260,295.65 | 4.00       |
| 11–20%        | 9,963       | 24,894      | $288.19       | $2,871,210.00 | 4.00       |
| 21–30%        | 5,003       | 12,571      | $245.08       | $1,226,129.80 | 4.00       |


**Finding.** Average revenue per order falls monotonically from $347 (no discount) to $245 (21–30% discount) while the average rating stays essentially flat at 4.00. Deeper discounts therefore **erode margin without buying satisfaction**. This is a direct, quantified answer to a question the retailer previously had to guess at. The 30%+ bucket is empty because the dataset caps discounts at 30%.

#### Q2 — Brand-Level Price Sensitivity


| brand       | rev at 0% | rev 1–10% | rev 11–20% | rev 21–30% | total      |
| ----------- | --------- | --------- | ---------- | ---------- | ---------- |
| ASICS       | $295,880  | $562,979  | $489,782   | $212,822   | $1,561,463 |
| Nike        | $303,670  | $554,731  | $460,973   | $205,208   | $1,524,582 |
| New Balance | $298,453  | $523,480  | $483,362   | $206,106   | $1,511,402 |
| Puma        | $283,910  | $527,531  | $485,525   | $202,129   | $1,499,095 |
| Reebok      | $274,810  | $562,686  | $463,529   | $197,616   | $1,498,641 |
| Adidas      | $267,090  | $528,889  | $488,038   | $202,250   | $1,486,267 |


**Finding.** Total revenue spreads only ~5% across brands, and the full-price (0%) column is similarly tight — in this synthetic dataset **no brand is dramatically more discount-dependent than another**. In real retail data, this same view would immediately expose brands whose 0% column is anomalously low (discount-dependent) vs brands whose 0% column is strong (price-holding).

#### Q6 — Geography & Demand Concentration


| country  | orders | units  | revenue    | avg rating | % Low | % Medium | % High |
| -------- | ------ | ------ | ---------- | ---------- | ----- | -------- | ------ |
| UAE      | 5,118  | 12,818 | $1,546,443 | 4.01       | 31.9  | 35.1     | 33.0   |
| UK       | 5,058  | 12,662 | $1,532,300 | 4.00       | 34.1  | 32.9     | 33.0   |
| India    | 4,991  | 12,539 | $1,520,899 | 4.00       | 34.0  | 32.0     | 34.0   |
| USA      | 5,027  | 12,472 | $1,511,747 | 3.99       | 32.6  | 33.9     | 33.5   |
| Germany  | 4,965  | 12,452 | $1,503,895 | 4.00       | 33.7  | 32.9     | 33.4   |
| Pakistan | 4,841  | 12,063 | $1,466,165 | 4.01       | 32.6  | 33.1     | 34.4   |


**Finding.** Revenue is distributed, not concentrated — the top and bottom markets differ by only 5.5%. Income mix is near-uniform at ~33/33/33 across all countries. In genuine retail data, asymmetries in this table identify where to push inventory and which markets have unserved income segments.

#### Q5 — Top 10 Satisfaction Drivers (by average rating)


| brand       | category   | gender | price band      | orders | avg rating | revenue |
| ----------- | ---------- | ------ | --------------- | ------ | ---------- | ------- |
| New Balance | Training   | Men    | Budget (<$75)   | 14     | 4.44       | $1,981  |
| ASICS       | Basketball | Men    | Budget (<$75)   | 11     | 4.35       | $1,673  |
| Nike        | Gym        | Unisex | Budget (<$75)   | 12     | 4.34       | $1,547  |
| Adidas      | Basketball | Women  | Mid ($75–150)   | 17     | 4.32       | $3,490  |
| Adidas      | Gym        | Women  | Budget (<$75)   | 13     | 4.32       | $2,082  |
| Adidas      | Gym        | Unisex | Budget (<$75)   | 10     | 4.32       | $1,771  |
| Reebok      | Basketball | Unisex | Budget (<$75)   | 10     | 4.31       | $1,470  |
| Adidas      | Running    | Women  | Premium ($150+) | 21     | 4.30       | $6,805  |
| Nike        | Running    | Women  | Budget (<$75)   | 13     | 4.30       | $1,858  |
| New Balance | Gym        | Unisex | Premium ($150+) | 18     | 4.29       | $6,273  |


**Finding.** Budget (<$75) combinations dominate 7 of the top 10 ratings — evidence that **value perception outweighs absolute price** in driving satisfaction. Adidas appears four times, suggesting a cross-category quality halo worth preserving in assortment decisions.

### 5.4 Remaining Questions

Q3 (category × tier matrix), Q4 (channel pricing), Q7 (size/colour demand), Q8 (temporal trends), and Q9 (rating vs discount) all produce comparable outputs and are runnable end-to-end from `queries.sql`. Their full outputs are available in the accompanying SQL file.

---

## 6. Ethics & Privacy

### 6.1 Risks Identified

The intermediate proposal identified three concrete risks:

1. Sensitive attributes (`customer_income_level`, `customer_rating`) could enable discriminatory pricing if exposed to pricing analysts.
2. Methodology could be transferred to real PII-rich data without re-review.
3. Individual-level profiling could be re-introduced if customer identifiers were added later.

### 6.2 Mitigations Implemented

#### Database-enforced role separation

The proposal committed to "restricted-access tables with role-based access controls." That commitment is now **implemented in SQL and enforced by the database engine**, not merely described:

```sql
CREATE ROLE analyst_pricing   LOGIN PASSWORD '…';
CREATE ROLE analyst_behavior  LOGIN PASSWORD '…';

-- Pricing analyst sees pricing views + product/channel dimensions,
-- but NOT Orders, NOT IncomeLevels, and NOT any behaviour view.
GRANT SELECT ON v_discount_tier_revenue,
                v_brand_price_sensitivity,
                v_category_discount_effectiveness,
                v_channel_pricing_behavior
            TO analyst_pricing;

-- Behaviour analyst sees aggregated behaviour views, but NOT raw
-- Orders (which would expose individual transactions + ratings).
GRANT SELECT ON v_satisfaction_drivers,
                v_geography_demand,
                v_size_color_demand,
                v_temporal_trends,
                v_rating_vs_discount
            TO analyst_behavior;
```

Verification (from `verify.py`):

```
[PASS] analyst_pricing CAN read v_discount_tier_revenue
[PASS] analyst_pricing BLOCKED from orders
```

A pricing analyst running `SELECT customer_rating FROM orders` receives `ERROR: permission denied for table orders` — enforced by Postgres, requiring no application-layer cooperation.

#### No personal identifiers designed in

The schema contains no customer name, email, phone, address, or unique identity field, and none can be added without a visible schema migration. Individual-level repeat-purchase or loyalty analysis is structurally impossible against this schema.

#### Aggregate-only reporting

All nine analytic views produce group-level summaries — average revenue by discount tier, satisfaction scores by brand-category combination, revenue by country. No view returns data at the individual transaction level. This prevents re-identification and is consistent with data-minimisation principles under GDPR and CCPA.

#### Restricted use scope

The findings are scoped to two legitimate retail use cases: pricing-strategy analysis and product-assortment planning. Extension of the methodology to dynamic personalised pricing, individual consumer credit scoring, or location-level surveillance is out of scope and would require a separate ethical review before such extensions could be made.

### 6.3 Why the Synthetic Dataset Still Matters Ethically

The Kaggle dataset is synthetic, which materially reduces direct privacy risk. However, the methodology is directly transferable to real transactional data, and demographic proxies (income level, country) become genuinely sensitive when applied to real records. Building the access-control layer now ensures that a future swap to real data inherits the same protections automatically.

---

## 7. Verification & Validation

### 7.1 Test Suite

An automated Python script (`verify.py`) runs 27 checks across five categories. All 27 pass.

**Category 1 — Row-count integrity (9 checks).**
Confirms table row counts match expectation after ETL: 30,000 orders, 6 brands, 5 categories, 3 genders, 2 channels, 6 countries, 4 payment methods, 3 income levels, and zero NULLs in foreign-key columns.

**Category 2 — Constraint rejection (5 checks).**
Each check attempts an intentionally invalid INSERT and verifies the database rejects it with the correct error class:

- `discount_percent = 150` → `CheckViolation` ✓
- `units_sold = 0` → `CheckViolation` ✓
- `customer_rating = 9.0` → `CheckViolation` ✓
- `base_price = -50` → `CheckViolation` ✓
- Non-existent `country_id = 9999` → `ForeignKeyViolation` ✓

**Category 3 — View correctness vs pandas (10 checks).**
The script independently recomputes discount-tier revenue totals and country revenue totals directly from the CSV using pandas, then compares them to the view output. All ten match to the cent:

```
[PASS] discount_tier '0%'    total_revenue matches — pandas=1,723,813.00 db=1,723,813.00
[PASS] discount_tier '1-10%' total_revenue matches — pandas=3,260,295.65 db=3,260,295.65
…
[PASS] country 'UAE' total_revenue matches — pandas=1,546,442.55 db=1,546,442.55
```

This proves the schema, ETL, and view logic preserve the semantics of the raw data exactly.

**Category 4 — Normalisation smell-test (1 check).**
Queries `information_schema` for any text column named `brand_name`, `category_name`, `country_name`, etc., appearing on a base table outside its designated dimension. Returns empty, confirming 3NF is not violated in the storage layer.

**Category 5 — Role enforcement smoke test (2 checks).**
Connects as `analyst_pricing` and verifies the role can read its permitted view but is blocked from `Orders`.

### 7.2 Summary

```
=== Summary ===
  PASS: 27
  FAIL: 0
```

Every layer of the stack — schema, ETL, views, constraints, roles — is independently verified against the raw CSV. The verification suite is re-runnable and serves as a regression test for future changes.

---

## 8. Future Work

### 8.1 Web Application

The next milestone is a web application that surfaces the eight analytics views to retailers. The schema is already structured to support it: each view maps cleanly to a single API endpoint, each endpoint to a dashboard tile, and the role-based access control already provides per-user data scoping.

A suggested minimal stack:

- **Backend:** FastAPI (Python) — one endpoint per view, SQL pass-through, role selected from the logged-in user.
- **Frontend:** React or plain HTML + Chart.js — eight dashboard tiles, one per question.
- **Auth:** Postgres-role-backed login; the webapp connects as `analyst_pricing` or `analyst_behavior` based on the authenticated user. The database engine itself enforces what each user can query.

This architecture means the sensitive-data controls survive into production — the webapp cannot accidentally leak data the database role cannot read.

### 8.2 Additional Enhancements (Not in Scope)

- **Materialised views** for the larger aggregations (`v_temporal_trends`, `v_size_color_demand`) if the dataset grows beyond 10× the current size.
- **Data-warehouse migration** — star-schema mart built on top of this 3NF core if analytical workloads start dominating transactional load.
- **Live data integration** — once a real retailer's POS system is wired in, the same schema, views, and roles apply without modification.

---

## 9. Conclusion

Starting from a flat 30,000-row CSV and an initial ER sketch, this project produced a complete, verified analytics-ready database: ten tables in third normal form, nine analytic views answering eight retailer-relevant questions, database-enforced role-based access control implementing the ethics commitments made in the proposal, and a 27-check automated verification suite confirming every layer against the raw data.

Two key design corrections made during development deserve particular note: removing the fabricated `Customers` entity once it became clear the data could not support it, and re-keying `Products` on `(brand, model, category, gender)` once the data profile showed `model_name` alone was not a product identifier. These changes tightened the design and prevented answering questions the data could not honestly support — which is itself a core lesson of database design.

---

## Appendix A — File Index


| File             | Purpose                                          |
| ---------------- | ------------------------------------------------ |
| `schema.sql`     | PostgreSQL DDL — 10 tables, constraints, indexes |
| `etl.py`         | CSV → database loader (idempotent)               |
| `views.sql`      | 1 base view + 9 analytic views                   |
| `roles.sql`      | Role creation and column-level GRANTs            |
| `queries.sql`    | Sample query per analytics question              |
| `verify.py`      | Automated 27-check verification suite            |
| `er_diagram.mmd` | Mermaid ER diagram source                        |
| `report.md`      | This report                                      |


## Appendix B — How to Reproduce

```bash
# 1. Create database and schema
createdb footwear_analytics
psql -d footwear_analytics -f schema.sql

# 2. Load data
python3 etl.py

# 3. Create views and roles
psql -d footwear_analytics -f views.sql
psql -d footwear_analytics -f roles.sql

# 4. Run analytics
psql -d footwear_analytics -f queries.sql

# 5. Run verification
python3 verify.py   # expects: PASS 27, FAIL 0
```