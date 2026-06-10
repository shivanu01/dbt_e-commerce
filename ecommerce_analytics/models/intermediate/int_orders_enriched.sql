with orders as (
    select * from {{ref('stg_orders')}}
),

payments as(
    select 
        order_id,
        count(*) as payment_attempt_count,
        max(case when payment_status = 'success' then 1 else 0 end) as has_successfull_payment,
        max(case when payment_status='refunded' then 1 else 0 end) as has_refund,
        min(case when payment_status='success' then payment_method end) as successfull_payment_method,
        sum(case when payment_status = 'success' then payment_amount else 0 end) as total_collected,
        sum(case when payment_status='refunded' then payment_amount else 0 end) as total_refunded

    from
        {{ref('stg_payments')}}
    group by 
        order_id
),

order_items as (
    select 
        order_id,
        count(*) as item_count,
        sum(quantity) as total_units,
        sum(line_total) as items_subtotal,
        sum(item_discount) as items_discount_total

    from
        {{ref('stg_order_items')}}
    group by order_id
),

enriched as (
    Select 
        o.order_id,
        o.customer_id,

        o.order_date,
        o.created_at,
        o.updated_at,
        o.order_status,
        o.is_returned,
        o.is_voided,
        o.coupon_code,

        o.subtotal,
        o.discount_amount,
        o.tax_amount,
        o.order_total,

        coalesce(oi.item_count,0) as item_count,
        coalesce(oi.total_units,0) as total_units,
        coalesce(oi.items_subtotal,0) as items_subtotal,
        coalesce(oi.items_discount_total, 0) as items_discount_total,
        
        coalesce(p.payment_attempt_count,0) as payment_attempt_count,
        coalesce(p.has_successfull_payment,0) as has_successfull_payment,
        coalesce(p.has_refund,0) as has_refund,
        p.successfull_payment_method,
        coalesce(p.total_collected,0) as total_collected,
        coalesce(p.total_refunded,0) as total_refunded,

        coalesce(p.total_collected,0) - coalesce(p.total_refunded,0) as net_revenue,

        case
            when o.order_status = 'delivered'  then 'fulfilled'
            when o.order_status = 'shipped'    then 'in_transit'
            when o.order_status = 'returned'   then 'returned'
            when o.order_status = 'cancelled'  then 'cancelled'
            when o.order_status = 'pending'    then 'pending'
            else 'unknown'
        end as fulfilment_status,


        datediff('day',o.order_date,coalesce(try_to_date(to_varchar(o.updated_at)),o.order_date)) as days_to_resolution,

        case 
            when o.order_status = 'delivered' and coalesce(p.has_successfull_payment,0) = 1 and coalesce(p.has_refund,0) = 0
            then true
            else false
        end as is_completed_order,

    _loaded_at

    from
        orders o 
    left join
        payments p
        on o.order_id = p.order_id
    left join
        order_items oi 
    on o.order_id = oi.order_id

)

select * from enriched