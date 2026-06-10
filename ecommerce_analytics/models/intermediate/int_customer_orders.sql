with  orders as (
    select * from {{ref('int_orders_enriched')}}
),

customers as (
    select 
        customer_id,
        full_name,
        email,
        country_code,
        signup_date,
        account_status
    from 
        {{ref('stg_customer')}}
),

orders_with_history as (
    select 
        o.*,

        row_number() over(partition by o.customer_id order by o.order_date,o.order_id) as customer_order_number,

        case 
            when row_number() over(partition by o.customer_id order by o.order_date,o.order_id) = 1 then true 
            else false 
            end as is_first_order,
        
        lag(o.order_date) over(partition by o.customer_id order by o.order_date,o.order_id) as previous_order_date,

        datediff('day',lag(o.order_date) over(partition by o.customer_id order by o.order_date,o.order_id),o.order_date) 
         as days_since_previous_order,

        sum(o.net_revenue) over(partition by o.customer_id order by o.order_date,o.order_id
            rows between unbounded preceding and current row) as running_lifetime_value,

        sum(case when o.is_completed_order then 1 else 0 end ) over(partition by o.customer_id order by o.order_date,o.order_id
            rows between unbounded preceding and current row) as running_completed_order_count

        from orders o 
        where o.is_voided = false
        
        ),
    final as (
        select 
        oh.order_id,
        oh.customer_id,
        oh.order_date,
        oh.order_status,
        oh.fulfilment_status,
        oh.is_voided,
        oh.order_total,
        oh.subtotal,
        oh.discount_amount,
        oh.tax_amount,
        oh.net_revenue,
        oh.item_count,
        oh.items_subtotal,
        oh.items_discount_total,
        oh.total_units,
        oh.payment_attempt_count,
        oh.has_successfull_payment,
        oh.has_refund,
        oh.successfull_payment_method,
        oh.total_collected,
        oh.total_refunded,
        oh.is_completed_order,
        oh.is_returned,
        oh.coupon_code,
        oh.days_to_resolution,

        oh.customer_order_number,
        oh.is_first_order,
        oh.previous_order_date,
        oh.days_since_previous_order,
        oh.running_lifetime_value,
        oh.running_completed_order_count,

        c.full_name  as customer_name,
        c.email  as customer_email,
        c.country_code,
        c.signup_date  as customer_signup_date,
        c.account_status  as customer_account_status,
        datediff('day',c.signup_date,oh.order_date) as days_since_signup,
        oh._loaded_at

        from orders_with_history oh 
        left join customers c 
        on oh.customer_id = c.customer_id
    )

select * from final