-- stg_products.sql
-- Source: RAW_DB.LANDING.RAW_PRODUCTS
-- One row per product in the catalogue.

with source as (

    select * from {{ source('ecommerce', 'RAW_PRODUCTS') }}

),

renamed as (

    select
        -- primary key
        id                                          as product_id,

        -- product details
        trim(name)                                  as product_name,
        initcap(trim(category))                     as category,
        initcap(trim(subcategory))                  as subcategory,
        upper(trim(sku))                            as sku,

        -- pricing: cents → dollars
        round(cost_cents  / 100.0, 2)              as cost_price,
        round(price_cents / 100.0, 2)              as retail_price,

        -- derived: gross margin percentage
        round(
            (price_cents - cost_cents) * 100.0 / nullif(price_cents, 0)
        , 2)                                        as gross_margin_pct,

        -- status: raw is 'true'/'false' string → boolean
        case
            when lower(trim(is_active)) = 'true' then true
            else false
        end                                         as is_active,

        -- dates
        try_to_date(created_at, 'YYYY-MM-DD')       as created_at,

        -- metadata
        _loaded_at

    from source

)

select * from renamed