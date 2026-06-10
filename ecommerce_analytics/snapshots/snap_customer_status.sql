{% snapshot snap_customer_status %}

{{
    config(
        target_schema = 'snapshots',
        unique_key = 'customer_id',
        strategy = 'check',
        check_cols = ['account_status','city','email']
    )
}}

select 
    customer_id,
    full_name,
    email,
    country_code,
    city,
    account_status,
    is_active,
    signup_date,
    _loaded_at as source_loaded_at
from {{ref('stg_customer')}}

{% endsnapshot %}