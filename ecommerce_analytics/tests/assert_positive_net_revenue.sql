-- tests/assert_positive_net_revenue.sql
-- Business rule: completed orders must never have negative net revenue.
-- A negative value means a refund exceeded the original payment
-- which indicates a data pipeline bug.
-- TEST PASSES if this returns 0 rows.
-- TEST FAILS if any rows come back — shows exactly which orders are wrong.

SELECT
    order_id,
    customer_id,
    order_date,
    net_revenue,
    order_status,
    total_amount_refunded,
    total_amount_collected
FROM {{ ref('fact_orders') }}
WHERE is_completed_order = true
AND net_revenue < 0