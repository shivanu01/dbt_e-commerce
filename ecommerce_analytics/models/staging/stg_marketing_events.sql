-- stg_marketing_events.sql
-- Source: RAW_DB.LANDING.RAW_MARKETING_EVENTS
-- One row per marketing event. Flattens VARIANT properties column.
-- Casts occurred_at from string to timestamp.

with source as (

    select * from {{ source('ecommerce', 'RAW_MARKETING_EVENTS') }}

),

-- Deduplicate: keep latest loaded row per event_id
deduplicated as (

    select *
    from source
    qualify row_number() over (
        partition by event_id
        order by _fetched_at desc
    ) = 1

),

renamed as (

    select
        -- primary key
        event_id,

        -- event details
        lower(trim(event_type))                         as event_type,

        -- identity
        customer_id,                                    -- nullable
        anonymous_id,
        session_id,

        -- timing
        try_to_timestamp(occurred_at)                   as occurred_at,
        date_trunc('month', try_to_timestamp(occurred_at)) as event_month,

        -- derived: is this a known customer or anonymous?
        case
            when customer_id is not null then 'known'
            else 'anonymous'
        end                                             as customer_type,

        -- flattened properties
        nullif(trim(page_url),      '')                 as page_url,
        product_id,
        nullif(trim(campaign_id),   '')                 as campaign_id,
        nullif(trim(email_subject), '')                 as email_subject,

        -- revenue: cents to dollars
        round(coalesce(revenue_cents, 0) / 100.0, 2)   as revenue,

        -- full properties blob preserved
        properties,

        -- derived event category
        case
            when event_type in ('page_view', 'search')
                then 'awareness'
            when event_type in ('add_to_cart', 'wishlist_add')
                then 'consideration'
            when event_type in ('checkout_started')
                then 'intent'
            when event_type in ('purchase')
                then 'conversion'
            when event_type in ('email_open', 'email_click')
                then 'retention'
            else 'other'
        end                                             as event_category,

        -- ingestion metadata
        _fetched_at,
        _batch_id

    from deduplicated

)

select * from renamed