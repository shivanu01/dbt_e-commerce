-- tests/assert_payment_not_exceed_order.sql
-- Business rule: total_amount_collected should never exceed order_total
-- by more than $1.00 (allowing for minor rounding differences).
-- If it does, payments are being double-counted somewhere.

SELECT
    order_id,
    order_total,
    total_amount_collected,
    total_amount_collected - order_total AS overage
FROM {{ ref('fact_orders') }}
WHERE total_amount_collected > order_total + 1.00
AND payment_is_successful = true