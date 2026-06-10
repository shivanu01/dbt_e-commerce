
with source as (

    select * from {{ source('ecommerce', 'RAW_SESSIONS') }}

),

renamed as (

    select
        
        id as session_id,

        -- identity
        anonymous_id,
        customer_id, 
        try_to_timestamp(session_start)   as session_started_at,
        try_to_timestamp(session_end)     as session_ended_at,

        datediff(
            'second',
            try_to_timestamp(session_start),
            try_to_timestamp(session_end)) as session_duration_seconds,

        -- attribution
        lower(trim(channel))  as channel,
        nullif(trim(utm_source),   '')  as utm_source,
        nullif(trim(utm_medium),   '')  as utm_medium,
        nullif(trim(utm_campaign), '')  as utm_campaign,

        -- behaviour
        nullif(trim(landing_page), '')  as landing_page,
        lower(trim(device_type))   as device_type,
        upper(trim(country_code))  as country_code,

        -- conversion: raw is 'true'/'false' string → boolean
        case
            when lower(trim(converted)) = 'true' then true
            else false
        end    as did_convert,
        order_id,  
        _loaded_at

    from source

)

select * from renamed