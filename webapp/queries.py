from db import get_cursor


def _rows(sql, params=None):
    with get_cursor() as cur:
        cur.execute(sql, params or ())
        return [dict(r) for r in cur.fetchall()]


def q1():
    return _rows("SELECT * FROM v_discount_tier_revenue")


def q2():
    return _rows("SELECT * FROM v_brand_price_sensitivity")


def q3():
    return _rows("SELECT * FROM v_category_discount_effectiveness")


def q4():
    return _rows("SELECT * FROM v_channel_pricing_behavior")


def q5(limit: int = 20):
    return _rows(
        """
        SELECT * FROM v_satisfaction_drivers
        ORDER BY avg_rating DESC
        LIMIT %s
        """,
        (limit,),
    )


def q6():
    return _rows("SELECT * FROM v_geography_demand")


def q7(category: str = "Running", limit: int = 30):
    return _rows(
        """
        SELECT category_name, size, color,
               SUM(order_count)  AS order_count,
               SUM(total_units)  AS total_units,
               SUM(total_revenue) AS total_revenue
        FROM v_size_color_demand
        WHERE category_name = %s
        GROUP BY category_name, size, color
        ORDER BY total_units DESC
        LIMIT %s
        """,
        (category, limit),
    )


def q8(groupby: str = "year"):
    if groupby == "year":
        return _rows(
            """
            SELECT year, category_name,
                   SUM(total_revenue) AS revenue
            FROM v_temporal_trends
            GROUP BY year, category_name
            ORDER BY year, category_name
            """
        )
    return _rows(
        """
        SELECT month, month_name, category_name,
               SUM(total_revenue) AS revenue
        FROM v_temporal_trends
        GROUP BY month, month_name, category_name
        ORDER BY category_name, month
        """
    )


def q9():
    return _rows("SELECT * FROM v_rating_vs_discount")


def categories():
    return _rows(
        "SELECT DISTINCT category_name FROM v_size_color_demand ORDER BY category_name"
    )
