-- tests/assert_order_total_not_negative.sql
-- Business rule: order_total must always be zero or positive.
-- Negative order totals indicate corrupted source data.

SELECT
    order_id,
    customer_id,
    order_date,
    order_total,
    subtotal,
    discount_amount
FROM {{ ref('fact_orders') }}
WHERE order_total < 0