-- models/marts/reporting/agg_cohort_retention.sql
-- Cohort retention analysis.
-- Shows what % of customers from each signup month reorder in subsequent months.
-- Classic retention matrix — essential for product/growth teams.

{{
    config(
        materialized = 'table',
        description  = 'Monthly cohort retention. Shows reorder rates by signup cohort.'
    )
}}

with orders as (

    select * from {{ ref('fact_orders') }}
    where is_completed_order = true

),

-- Step 1: Find each customer's cohort (month of first order)
customer_cohorts as (

    select
        customer_id,
        date_trunc('month', min(order_date))  as cohort_month,
        min(order_date) as first_order_date
    from orders
    group by customer_id

),

-- Step 2: For every order, calculate how many months after
-- the cohort month it happened
order_with_cohort as (

    select
        o.customer_id,
        o.order_date,
        o.order_month,
        c.cohort_month,

        -- months between first order and this order
        datediff('month', c.cohort_month, o.order_month) as months_since_first_order

    from orders             o
    join customer_cohorts   c on o.customer_id = c.customer_id

),

-- Step 3: Count how many unique customers per cohort per month offset
cohort_counts as (

    select
        cohort_month,
        months_since_first_order,
        count(distinct customer_id)  as customers

    from order_with_cohort
    group by cohort_month, months_since_first_order

),

-- Step 4: Get cohort sizes (month 0 count = total cohort size)
cohort_sizes as (

    select
        cohort_month,
        customers   as cohort_size
    from cohort_counts
    where months_since_first_order = 0

),

final as (

    select
        cc.cohort_month,
        cs.cohort_size,
        cc.months_since_first_order,
        cc.customers     as retained_customers,

        -- retention rate: what % of original cohort came back?
        round(
            cc.customers * 100.0
            / nullif(cs.cohort_size, 0)
        , 1)   as retention_rate_pct,

        -- month being measured
        dateadd('month',
            cc.months_since_first_order,
            cc.cohort_month
        )   as activity_month

    from cohort_counts    cc
    join cohort_sizes     cs on cc.cohort_month = cs.cohort_month
    order by cohort_month, months_since_first_order

)

select * from final