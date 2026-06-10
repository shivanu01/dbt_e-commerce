{{config(materialized = 'table' ,description = 'Customer master dimension. One row per customer.')}}

with customer_lifetime as 
(
    select * from {{ref('int_customer_lifetime')}}
),

final as (
    Select customer_id,
    full_name,
    email,
    country_code,
    city,customer_lifespan_days,
    referral_code,
    case
        when referral_code is not null then true else false end as is_referred,

    signup_date,
    account_status,
    is_active,

    datediff('day',signup_date,current_date()) as days_as_member,
    year(signup_date) as signup_year,
    date_trunc('month',signup_date) as signup_month,

    total_orders,
    completed_orders,
    returned_orders,
    has_ever_ordered,
    first_order_date,
    most_recent_order_date,
    days_since_last_order,
   

    lifetime_value,
    avg_order_value,
    highest_order_value,
    return_rate_pct,
    coupon_usage_pct,

    customer_segment,
    ltv_quartile,
    
    -- Absolute tier: fixed business thresholds
    -- These don't change when new customers join

    case 
        when lifetime_value>=400 then 'gold'
        when lifetime_value>=200 then 'silver'
        when lifetime_value>=50 then 'bronze'
        when lifetime_value>0 then 'starter'
        else 'no_purchase'
    end as customer_tier,

    -- CHURN SIGNALS
    -- A customer is "at risk" if no order in 60 days
    -- A customer is "churned" if no order in 90 days

    case 
        when days_since_last_order>=90 then 'churned'
        when days_since_last_order>=60 then 'at_risk'
        when days_since_last_order>=30 then 'active'
        when days_since_last_order<30 then 'highly_active'
        else 'never_ordered'
        end as churn_status,
    
    case 
        when days_since_last_order>=90 then true else false end as is_churning,

    preferred_payment_method,
    review_count,
    avg_rating_given,

    case
        when review_count>=3 then true
        else false 
    end as is_active_reviewer

    from customer_lifetime


)

select * from final