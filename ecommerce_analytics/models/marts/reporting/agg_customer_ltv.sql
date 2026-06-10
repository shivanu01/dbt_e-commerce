-- models/marts/reporting/agg_customer_ltv.sql
-- Customer lifetime value distribution.
-- Breaks down revenue concentration by segment, country, tier.
-- Answers: where does our revenue come from and how concentrated is it?

{{
    config(
        materialized = 'table',
        description  = 'Customer LTV distribution by segment and geography.'
    )
}}

with customers as (

    select * from {{ ref('dim_customers') }}

),

-- Total revenue for percentage calculations
total_revenue as (

    select sum(lifetime_value) as grand_total_revenue
    from customers
    where lifetime_value > 0

),

-- Segment + country level aggregation
by_segment_country as (

    select
        c.customer_segment,
        c.customer_tier,
        c.country_code,

        -- counts
        count(*)                                        as customer_count,
        count(case when c.has_ever_ordered then 1 end)  as ordering_customers,
        count(case when c.is_churning      then 1 end)  as churning_customers,
        count(case when c.is_active        then 1 end)  as active_customers,

        -- revenue
        round(sum(c.lifetime_value),  2)                as total_ltv,
        round(avg(c.lifetime_value),  2)                as avg_ltv,
        round(min(c.lifetime_value),  2)                as min_ltv,
        round(max(c.lifetime_value),  2)                as max_ltv,
        round(avg(c.avg_order_value), 2)                as avg_order_value,

        -- order behaviour
        round(avg(c.total_orders),    2)                as avg_orders_per_customer,
        round(avg(c.return_rate_pct), 2)                as avg_return_rate,
        round(avg(c.coupon_usage_pct),2)                as avg_coupon_usage,
        round(avg(c.days_since_last_order), 0)          as avg_days_since_last_order,

        -- churn rate within this segment
        round(
            count(case when c.is_churning then 1 end) * 100.0
            / nullif(count(*), 0)
        , 1)                                            as churn_rate_pct,

        -- revenue share of total
        round(
            sum(c.lifetime_value) * 100.0
            / nullif(max(t.grand_total_revenue), 0)
        , 2)                                            as pct_of_total_revenue

    from customers          c
    cross join total_revenue t
    group by
        c.customer_segment,
        c.customer_tier,
        c.country_code

)

select * from by_segment_country
order by total_ltv desc