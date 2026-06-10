
with source as (

    select * from {{ source('ecommerce', 'RAW_REVIEWS') }}

),

renamed as (

    select
        id   as review_id,

        product_id,
        customer_id,
        order_id,
        rating,   
        nullif(trim(review_text), '')    as review_text,

      
        case
            when rating >= 4 then 'positive'
            when rating = 3  then 'neutral'
            else                  'negative'
        end   as sentiment,

        -- dates
        try_to_date(submitted_at, 'YYYY-MM-DD')  as submitted_at,

        -- verification
        case
            when lower(trim(is_verified)) = 'true' then true
            else false
        end     as is_verified,

        -- metadata
        _loaded_at

    from source

)

select * from renamed