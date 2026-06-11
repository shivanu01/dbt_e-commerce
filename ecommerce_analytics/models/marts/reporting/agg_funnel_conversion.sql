{{ config(materialized='table') }}

with sessions as (

    select * from {{ ref('stg_sessions') }}

),

orders as (

    select * from {{ ref('fact_orders') }}
    where is_completed_order = true

),

-- NEW: marketing events aggregated by campaign
marketing_events as (

    select
        campaign_id,
        event_month,
        count(*)                                                as total_events,
        count(distinct customer_id)                             as unique_customers,
        count(case when event_type = 'page_view'         then 1 end) as page_views,
        count(case when event_type = 'add_to_cart'       then 1 end) as add_to_carts,
        count(case when event_type = 'checkout_started'  then 1 end) as checkouts_started,
        count(case when event_type = 'purchase'          then 1 end) as purchases,
        round(sum(revenue), 2)                                  as api_revenue,

        -- conversion funnel rates
        round(
            count(case when event_type = 'add_to_cart' then 1 end) * 100.0
            / nullif(count(case when event_type = 'page_view' then 1 end), 0)
        , 1)                                                    as add_to_cart_rate,

        round(
            count(case when event_type = 'purchase' then 1 end) * 100.0
            / nullif(count(case when event_type = 'checkout_started' then 1 end), 0)
        , 1)                                                    as checkout_conversion_rate

    from {{ ref('stg_marketing_events') }}
    where campaign_id is not null
    group by campaign_id, event_month

),

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
        o.order_id,
        o.order_total,
        o.net_revenue,
        o.is_first_order,
        o.customer_id,
        o.customer_segment
    from sessions               s
    left join orders            o on s.order_id = o.order_id

),

channel_summary as (

    select
        channel,
        count(*)                                                as total_sessions,
        count(case when did_convert then 1 end)                 as converted_sessions,
        round(
            count(case when did_convert then 1 end) * 100.0
            / nullif(count(*), 0)
        , 1)                                                    as conversion_rate_pct,
        round(avg(session_duration_seconds), 0)                 as avg_session_duration_secs,
        round(sum(coalesce(net_revenue, 0)), 2)                 as total_revenue,
        round(avg(case when did_convert then order_total end), 2) as avg_order_value,
        round(
            sum(coalesce(net_revenue, 0)) / nullif(count(*), 0)
        , 2)                                                    as revenue_per_session,
        count(distinct customer_id)                             as unique_customers,
        count(case when is_first_order then 1 end)              as new_customers_acquired,
        round(
            count(case when is_first_order then 1 end) * 100.0
            / nullif(count(case when did_convert then 1 end), 0)
        , 1)                                                    as pct_new_customer_orders,
        count(case when device_type = 'mobile' then 1 end)      as mobile_sessions,
        count(case when device_type = 'desktop' then 1 end)     as desktop_sessions,
        round(
            count(case when device_type = 'mobile' then 1 end) * 100.0
            / nullif(count(*), 0)
        , 1)                                                    as mobile_pct

    from session_with_order
    group by channel

),

-- Join channel summary with marketing events data
final as (

    select
        cs.*,

        -- marketing events enrichment
        coalesce(me.total_events,             0)    as total_marketing_events,
        coalesce(me.page_views,               0)    as total_page_views,
        coalesce(me.add_to_carts,             0)    as total_add_to_carts,
        coalesce(me.checkouts_started,        0)    as total_checkouts_started,
        coalesce(me.purchases,                0)    as total_purchases_from_events,
        coalesce(me.api_revenue,              0)    as api_tracked_revenue,
        coalesce(me.add_to_cart_rate,         0)    as add_to_cart_rate,
        coalesce(me.checkout_conversion_rate, 0)    as checkout_conversion_rate

    from channel_summary        cs
    left join marketing_events  me
        on lower(cs.channel) = lower(me.campaign_id)

)

select * from final
order by total_revenue desc