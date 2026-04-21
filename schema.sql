-- ============================================================
-- Global Sports Footwear Retailer Analytics
-- PostgreSQL schema (3NF normalized core)
-- ============================================================
-- Usage:
--   createdb footwear_analytics
--   psql -d footwear_analytics -f schema.sql
-- ============================================================

-- Clean slate (safe re-run)
DROP TABLE IF EXISTS Orders          CASCADE;
DROP TABLE IF EXISTS Products        CASCADE;
DROP TABLE IF EXISTS DateDim         CASCADE;
DROP TABLE IF EXISTS IncomeLevels    CASCADE;
DROP TABLE IF EXISTS PaymentMethods  CASCADE;
DROP TABLE IF EXISTS Channels        CASCADE;
DROP TABLE IF EXISTS Countries       CASCADE;
DROP TABLE IF EXISTS Genders         CASCADE;
DROP TABLE IF EXISTS Categories      CASCADE;
DROP TABLE IF EXISTS Brands          CASCADE;


-- ============================================================
-- 1. Dimension / lookup tables
-- ============================================================

CREATE TABLE Brands (
    brand_id   SERIAL PRIMARY KEY,
    brand_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE Categories (
    category_id   SERIAL PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE Genders (
    gender_id   SERIAL PRIMARY KEY,
    gender_name VARCHAR(20) NOT NULL UNIQUE
        CHECK (gender_name IN ('Men', 'Women', 'Unisex'))
);

CREATE TABLE Countries (
    country_id   SERIAL PRIMARY KEY,
    country_name VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE Channels (
    channel_id   SERIAL PRIMARY KEY,
    channel_name VARCHAR(30) NOT NULL UNIQUE
        CHECK (channel_name IN ('Online', 'Retail Store'))
);

CREATE TABLE PaymentMethods (
    payment_method_id SERIAL PRIMARY KEY,
    method_name       VARCHAR(30) NOT NULL UNIQUE
        CHECK (method_name IN ('Card', 'Cash', 'Wallet', 'Bank Transfer'))
);

CREATE TABLE IncomeLevels (
    income_level_id SERIAL PRIMARY KEY,
    level_name      VARCHAR(10) NOT NULL UNIQUE
        CHECK (level_name IN ('Low', 'Medium', 'High'))
);

CREATE TABLE DateDim (
    date_id       INT         PRIMARY KEY,      -- YYYYMMDD surrogate
    full_date     DATE        NOT NULL UNIQUE,
    year          SMALLINT    NOT NULL,
    quarter       SMALLINT    NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    month         SMALLINT    NOT NULL CHECK (month BETWEEN 1 AND 12),
    month_name    VARCHAR(10) NOT NULL,
    week_of_year  SMALLINT    NOT NULL CHECK (week_of_year BETWEEN 1 AND 53),
    day_of_week   SMALLINT    NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    is_weekend    BOOLEAN     NOT NULL
);


-- ============================================================
-- 2. Products (logical SKU)
-- ============================================================

CREATE TABLE Products (
    product_id  SERIAL      PRIMARY KEY,
    brand_id    INT         NOT NULL REFERENCES Brands(brand_id),
    model_name  VARCHAR(50) NOT NULL,
    category_id INT         NOT NULL REFERENCES Categories(category_id),
    gender_id   INT         NOT NULL REFERENCES Genders(gender_id),
    UNIQUE (brand_id, model_name, category_id, gender_id)
);


-- ============================================================
-- 3. Orders (transactional fact)
-- ============================================================

CREATE TABLE Orders (
    order_id          VARCHAR(20) PRIMARY KEY,
    date_id           INT         NOT NULL REFERENCES DateDim(date_id),
    product_id        INT         NOT NULL REFERENCES Products(product_id),
    country_id        INT         NOT NULL REFERENCES Countries(country_id),
    channel_id        INT         NOT NULL REFERENCES Channels(channel_id),
    payment_method_id INT         NOT NULL REFERENCES PaymentMethods(payment_method_id),
    income_level_id   INT         NOT NULL REFERENCES IncomeLevels(income_level_id),

    size              SMALLINT       NOT NULL CHECK (size BETWEEN 1 AND 20),
    color             VARCHAR(30)    NOT NULL,
    base_price_usd    NUMERIC(8,2)   NOT NULL CHECK (base_price_usd > 0),
    discount_percent  NUMERIC(5,2)   NOT NULL CHECK (discount_percent BETWEEN 0 AND 100),
    units_sold        INT            NOT NULL CHECK (units_sold > 0),
    customer_rating   NUMERIC(2,1)   NOT NULL CHECK (customer_rating BETWEEN 3.0 AND 5.0)
);


-- ============================================================
-- 4. Indexes on FKs (query performance for analytics)
-- ============================================================

CREATE INDEX idx_orders_date     ON Orders(date_id);
CREATE INDEX idx_orders_product  ON Orders(product_id);
CREATE INDEX idx_orders_country  ON Orders(country_id);
CREATE INDEX idx_orders_channel  ON Orders(channel_id);
CREATE INDEX idx_orders_income   ON Orders(income_level_id);
CREATE INDEX idx_orders_payment  ON Orders(payment_method_id);
