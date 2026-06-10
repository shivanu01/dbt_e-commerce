-- stg_payments.sql
-- Source: RAW_DB.LANDING.RAW_PAYMENTS
-- One row per payment attempt. An order can have multiple payment rows
-- (e.g. a failed attempt followed by a successful one).

with source as (

    select * from {{ source('ecommerce', 'RAW_PAYMENTS') }}

),

renamed as (

    select
        -- primary key
        id                                          as payment_id,

        -- foreign key
        order_id,

        -- payment details
        lower(trim(payment_method))                 as payment_method,
        lower(trim(status))                         as payment_status,
        upper(trim(currency))                       as currency,

        -- amount: cents → dollars
        round(amount_cents / 100.0, 2)             as payment_amount,

        -- dates
        try_to_timestamp(processed_at)              as processed_at,

        -- reference
        nullif(trim(gateway_ref), '')               as gateway_ref,

        -- derived flags
        case
            when lower(trim(status)) = 'success'  then true
            else false
        end                                         as is_successful,

        case
            when lower(trim(status)) = 'refunded' then true
            else false
        end                                         as is_refunded,

        -- metadata
        _loaded_at

    from source

)

select * from renamed