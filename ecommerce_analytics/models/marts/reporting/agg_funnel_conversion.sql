-- models/marts/reporting/agg_funnel_conversion.sql
-- Marketing channel funnel analysis.
-- Connects sessions to orders to measure channel quality and ROI.
-- One row per channel.

{{
    config(
        materialized = 'table',
        description  = 'Channel funnel conversion. Sessions to revenue by marketing channel.'
    )
}}

with sessions as (

    select * from {{ ref('stg_sessions') }}

),

orders as (

    select * from {{ ref('fact_orders') }}
    where is_completed_order = true

),

-- Join sessions to orders on order_id
-- A session "converted" if it resulted in a completed order
session_with_order as (

    select
        s.session_id,
        s.channel,
        s.utm_source,
        s.utm_campaign,
        s.device_type,
        s.country_code,
        s.did_convert,
        s.session_duration_seconds,

        -- order details if converted
        o.order_id,
        o.order_total,
        o.net_revenue,
        o.is_first_order,
        o.customer_id,
        o.customer_segment

    from sessions               s
    left join orders            o on s.order_id = o.order_id

),

final as (

    select
      
        channel,

        count(*)                                    as total_sessions,
        count(case when did_convert then 1 end)     as converted_sessions,

        round(
            count(case when did_convert then 1 end) * 100.0
            / nullif(count(*), 0)
        , 1)                                        as conversion_rate_pct,

        round(avg(session_duration_seconds), 0)     as avg_session_duration_secs,

        
        round(sum(coalesce(net_revenue, 0)), 2)     as total_revenue,
        round(avg(case when did_convert
                       then order_total end), 2)    as avg_order_value,

        -- revenue per session = total revenue / total sessions
        -- key efficiency metric for paid channels
        round(
            sum(coalesce(net_revenue, 0))
            / nullif(count(*), 0)
        , 2)  as revenue_per_session,

      
        count(distinct customer_id)                 as unique_customers,
        count(case when is_first_order then 1 end)  as new_customers_acquired,
        count(case when customer_segment = 'vip'
                   then 1 end)                      as vip_orders,

        -- what % of conversions were new customers?
        round(
            count(case when is_first_order then 1 end) * 100.0
            / nullif(count(case when did_convert then 1 end), 0)
        , 1)                                        as pct_new_customer_orders,

        
        count(case when device_type = 'mobile'
                   then 1 end)                      as mobile_sessions,
        count(case when device_type = 'desktop'
                   then 1 end)                      as desktop_sessions,

        round(
            count(case when device_type = 'mobile' then 1 end) * 100.0
            / nullif(count(*), 0)
        , 1)                                        as mobile_pct

    from session_with_order
    group by channel
    order by total_revenue desc

)

select * from final