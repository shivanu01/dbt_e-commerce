{{config(materialized='table')}}

with orders as (
    select * from {{ref('fact_orders')}}
    where is_completed_order = true
),

daily as(
    Select 
        order_date,
        order_month,
        order_quarter,
        order_year,
        date_trunc('week',order_date) as order_week,
        dayname(order_date) as day_name,
        count(*) as total_orders, ---please confirm this once
        {# is_weekend_order as is_weekend, #}

        --order count

        count(*) as order_count,
        count(case when is_returned then 1 end) as returned_orders,
        count(case when is_first_order then 1 end) as first_orders,
        count(case when not is_first_order and not is_first_order then 1 end) as repeat_orders,
        count(case when has_coupon then 1 end) as coupon_orders,

        --revenue

        round(sum(order_total),2) as gross_revenue,
        round(sum(net_revenue),2) as net_revenue,
        round(sum(discount_amount), 2) as total_discounts,
        round(sum(tax_amount),  2)  as total_tax,
        round(sum(total_amount_refunded),  2)  as total_refunds,
        round(avg(order_total),   2)  as avg_order_value,
        round(avg(total_units),  2)   as avg_items_per_order,

        --revenue split by customer type

        round(sum(case when is_first_order then net_revenue else 0 end),2) as new_customer_revenue,
        round(sum(case when not is_first_order then net_revenue else 0 end),2) as repeat_customer_revenue,

        --customer_count
        count(distinct customer_id)  as unique_customers,
        count(distinct country_code) as unique_countries,

        --payment_breakdown

        count(case when payment_method ='upi' then 1 end) as upi_orders,
        count(case when payment_method = 'credit_card' then 1 end) as credit_card_orders,
        count(case when payment_method = 'paypal'then 1 end) as paypal_orders,
        count(case when had_payment_retry then 1 end) as retry_orders,

        --fulfilment

        round(avg(days_to_resolution),2) as avg_days_to_resolution

    from orders
    group by
        order_date,order_month,order_quarter,order_year,dayname(order_date)

),
    -- Add month-to-date running totals using window functions
with_running_total as (
    select daily.*,
    -- Running revenue within the same month
        sum(net_revenue) over(partition by order_month order by order_date
                            rows between unbounded preceding and current row ) as running_revenue_mtd,
        -- Running orders within the same month
        sum(total_orders) over (
            partition by order_month
            order by order_date
            rows between unbounded preceding and current row ) as running_orders_mtd,

        --7 day rolling avergae revenue

        round(avg(net_revenue) over( order by order_date rows between 6 preceding and current row),2) as revenue_7day_avg

    from daily

)

select * from with_running_total