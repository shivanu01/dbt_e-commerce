with customer_orders as (
    select * from {{ref('int_customer_orders')}}
),

customers as (
    select * from {{ref('stg_customer')}}
    ),

reviews as 
(
    select 
        customer_id ,
        count(*) as review_count,
        avg(rating) as avg_rating_given
    from
        {{ref('stg_reviews')}}
    group by customer_id
),
order_summary as (
    select 
        customer_id,
        count(*) as total_orders,
        count(case when is_completed_order then 1 end) as completed_orders,
        count(case when is_returned then 1 end)  as returned_orders,
        count(case when is_first_order then 1 end) as first_order_count,

        sum(net_revenue) as lifetime_value,
        avg(net_revenue) as avg_order_value,
        max(net_revenue) as highest_order_value,
        min(net_revenue) as lowest_order_value,

        min(order_date) as first_order_date,
        max(order_date) as most_recent_order_date,

        datediff('day',min(order_date),max(order_date)) as customer_lifespan_days,

        round(count(case when is_returned then 1 end)*100.0/nullif(count(*),0),2) as return_rate_pct,

        count(case when coupon_code is not null then 1 end) as orders_with_coupon,
        round(count(case when coupon_code is not null then 1 end)*100.0/nullif(count(*),0),2) as coupon_usage_pct

    from customer_orders
    group by customer_id
),

preferred_payment as (

    select
        customer_id,
        successfull_payment_method as preferred_payment_method
    from (
        -- Level 2: apply row_number on already-aggregated counts
        select
            customer_id,
            successfull_payment_method,
            usage_count,
            row_number() over (
                partition by customer_id
                order by usage_count desc    -- now referencing a column, not an aggregate
            ) as rn
        from (
            -- Level 1: aggregate first
            select
                customer_id,
                successfull_payment_method,
                count(*) as usage_count
            from customer_orders
            where successfull_payment_method is not null
            group by customer_id, successfull_payment_method
        )
    )
    where rn = 1

),

customer_segments as (
    select 
        customer_id,
        lifetime_value,
        ntile(4) over(order by lifetime_value) as ltv_quartile,

        case
            when ntile(4) over (order by lifetime_value) = 4 then 'vip'
            when ntile(4) over (order by lifetime_value) = 3 then 'loyal'
            when ntile(4) over (order by lifetime_value) = 2 then 'potential'
            else 'new'
        end as customer_segment
    from order_summary),
final as (

    select
    
        c.customer_id,
        c.full_name,
        c.email,
        c.country_code,
        c.city,
        c.signup_date,
        c.account_status,
        c.is_active,
        c.referral_code,

        
        coalesce(os.total_orders,0)  as total_orders,
        coalesce(os.completed_orders,0)  as completed_orders,
        coalesce(os.returned_orders, 0)  as returned_orders,
        coalesce(os.lifetime_value,0)  as lifetime_value,
        coalesce(os.avg_order_value,0)  as avg_order_value,
        coalesce(os.highest_order_value, 0)  as highest_order_value,
        os.first_order_date,
        os.most_recent_order_date,
        coalesce(os.customer_lifespan_days, 0)  as customer_lifespan_days,
        coalesce(os.return_rate_pct, 0)  as return_rate_pct,
        pp.preferred_payment_method,
        coalesce(os.coupon_usage_pct,0)  as coupon_usage_pct,

        datediff('day', os.most_recent_order_date, current_date()) as days_since_last_order,

        
        case
            when os.total_orders is null then false
            else true
        end  as has_ever_ordered,


        coalesce(cs.customer_segment, 'new')  as customer_segment,
        cs.ltv_quartile,

       
        coalesce(r.review_count,0)as review_count,
        r.avg_rating_given

    from customers c
    left join order_summary os on c.customer_id = os.customer_id
    left join preferred_payment pp on c.customer_id = pp.customer_id
    left join customer_segments cs on c.customer_id = cs.customer_id
    left join reviews r on c.customer_id = r.customer_id

)

select * from final

