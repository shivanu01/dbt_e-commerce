-- tests/assert_customer_lifespan_positive.sql
-- Business rule: customer_lifespan_days must be zero or positive.
-- Negative means first_order_date > most_recent_order_date which is impossible.
-- This catches date ordering bugs in int_customer_lifetime.

SELECT
    customer_id,
    full_name,
    first_order_date,
    most_recent_order_date,
    customer_lifespan_days
FROM {{ ref('dim_customers') }}
WHERE customer_lifespan_days < 0