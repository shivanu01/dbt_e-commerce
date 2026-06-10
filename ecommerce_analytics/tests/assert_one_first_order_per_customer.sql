-- tests/assert_one_first_order_per_customer.sql
-- Business rule: every customer must have exactly one first order.
-- Zero means the window function failed to mark any order as first.
-- Two or more means the window function has a bug.
-- Returns customers where the count is not exactly 1.

SELECT
    customer_id,
    COUNT(*) AS first_order_count
FROM {{ ref('fact_orders') }}
WHERE is_first_order = true
GROUP BY customer_id
HAVING COUNT(*) != 1