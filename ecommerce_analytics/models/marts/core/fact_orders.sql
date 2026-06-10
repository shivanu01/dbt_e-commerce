
{{
    config(
        materialized  = 'incremental',
        unique_key    = 'order_id',
        on_schema_change = 'sync_all_columns',
        description = 'Order fact table. One row per order. Central table for revenue analysis.'
    )
}}
with max_loaded as (

    {% if is_incremental() %}
        select max(order_date) as max_ts from {{ this }}
    {% else %}
        select cast('1900-01-01' as date) as max_ts
    {% endif %}

),

customer_orders as (

    select * from {{ ref('int_customer_orders') }}

    {% if is_incremental() %}
        where order_date > (select max_ts from max_loaded)
    {% endif %}

),

payment_rollups as (

    select * from {{ ref('int_payment_rollups') }}

    {% if is_incremental() %}
        where order_date > (select max_ts from max_loaded)
    {% endif %}

),
customers as (
    select
        customer_id,
        customer_segment,
        customer_tier,
        churn_status,
        is_referred
    from {{ref('dim_customers')}}
),

final as (
    select 
        co.order_id,
        co.customer_id,

        co.order_date,
        date_trunc('month',co.order_date) as order_month,
        date_trunc('quarter',co.order_date) as order_quarter,
        date_trunc('year', co.order_date) as order_year,
        dayname(co.order_date) as order_day_of_week,

        case 
            when dayname(co.order_date) in ('Sat','Sun') then true else false end as is_weekend_order,
        
        co.order_status,
        co.fulfilment_status,
        co.is_completed_order,
        co.is_returned,
        co.is_voided,
        co.coupon_code,

        case when coupon_code is not null then true else false end as has_coupon,

        co.customer_name,
        co.customer_email,
        co.country_code,
        co.customer_signup_date,
        co.customer_account_status,
        co.days_since_signup,
        co.customer_order_number,
        co.is_first_order,
        co.previous_order_date,
        co.days_since_previous_order,

        c.customer_segment,
        c.customer_tier,
        c.churn_status,
        c.is_referred,

        co.order_total,
        co.subtotal,
        co.discount_amount,
        co.tax_amount,
        co.net_revenue,

        co.item_count,
        co.total_units,
        co.items_subtotal,
        co.items_discount_total,

        pr.primary_payment_method as payment_method,
        pr.primary_payment_status as payment_status,
        pr.payment_is_successful,
        pr.payment_is_refunded,
        pr.total_payment_attempts,
        pr.total_amount_collected,
        pr.total_amount_refunded,
        pr.net_amount_collected,
        pr.failed_attempt_count,
        pr.had_payment_retry,
        pr.is_fully_paid,
        pr.minutes_to_payment_success,


        co.days_to_resolution,
        -- Add this after days_to_resolution:
        case
            when co.days_to_resolution <= 1 then 'same_day'
            when co.days_to_resolution <= 3 then 'fast'
            when co.days_to_resolution <= 7 then 'standard'
            else  'slow'
        end  as delivery_speed,

        current_timestamp() as dbt_loaded_at

    from customer_orders as co
    left join payment_rollups as pr on co.order_id = pr.order_id
    left join customers as c on co.customer_id = c.customer_id
)

select * from final