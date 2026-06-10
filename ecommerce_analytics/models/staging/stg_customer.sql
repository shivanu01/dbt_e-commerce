with source as (
    Select * from {{ source('ecommerce', 'RAW_CUSTOMERS') }}
),

renamed as (
    select id as customer_id,
    first_name,last_name,
    concat(first_name,' ',last_name) as full_name,
    lower(trim(email)) as email,
    trim(phone) as phone,
    upper(trim(country_code)) as country_code,
    initcap(trim(city)) as city,
    try_to_date(signup_date,'YYYY-MM-DD') as signup_date,
    lower(trim(account_status)) as account_status,
    nullif(trim(referral_code),'') as referral_code,
    case
        when lower(trim(account_status)) = 'active' then true
        else false
        end as is_active,
    
    _loaded_at
    from source
)

select * from renamed

