with source as (
    select * from {{source('ecommerce','RAW_ORDERS')}}
),

renamed as (
    select 
        id as order_id,
        customer_id,

        coalesce(
                try_to_date(order_date, 'YYYY-MM-DD'),
                try_to_date(order_date, 'DD-MM-YYYY'),
                try_to_date(order_date, 'MM/DD/YYYY'),
                try_to_date(order_date, 'YYYY/MM/DD')) as order_date,             
        try_to_timestamp(created_at) as created_at,
        try_to_timestamp(updated_at) as updated_at,
        lower(trim(status)) as order_status,
        shipping_address,
        billing_address,
        nullif(trim(coupon_code),'') as coupon_code,

        --financial conversion
        {{cents_to_dollars('subtotal_cents')}} as subtotal,
        {{cents_to_dollars('discount_cents')}} as discount_amount,
        {{cents_to_dollars('tax_cents')}} as tax_amount,
        {{cents_to_dollars('total_cents')}} as order_total,

        case 
            when lower(trim(status)) in ('cancelled','returned') then true
            else false 
            end as is_voided,

        case 
            when lower(trim(status)) = 'returned' then true
            else false
            end as is_returned,

        _loaded_at
        
    from 
        source

)

select * from renamed