-- tests/assert_delivered_orders_have_payment.sql
-- Business rule: every delivered order must have a successful payment.
-- If this returns rows it means we have delivered goods without receiving payment
-- which is a serious financial data integrity issue.

SELECT
    order_id,
    customer_id,
    order_date,
    order_status,
    payment_is_successful,
    payment_status,
    total_amount_collected
FROM {{ ref('fact_orders') }}
WHERE order_status = 'delivered'
AND (
    payment_is_successful = false
    OR payment_is_successful IS NULL
)