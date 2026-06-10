

with source as (

    select * from {{ source('ecommerce', 'RAW_ORDER_ITEMS') }}

),
deduplicated as (

    select *
    from source
    qualify row_number() over (
        partition by id
        order by _loaded_at desc    -- keep most recently loaded row
    ) = 1

),

renamed as (

    select
        
        id  as order_item_id,

        order_id,
        product_id,
        quantity,
        round(unit_price_cents  / 100.0, 2)   as unit_price,
        round(discount_cents    / 100.0, 2)   as item_discount,
        round(
            (unit_price_cents * quantity - discount_cents) / 100.0
        , 2)  as line_total,
         _loaded_at

    from deduplicated

)

select * from renamed