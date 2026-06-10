with payments as (
    select * from {{ref('stg_payments')}}
),

orders as (
    select 
        order_id,
        order_total,
        order_date,
        _loaded_at
    from 
        {{ref('stg_orders')}}
),

payment_ranked as (
    select 
        p.*,
        row_number() over(partition by p.order_id
        order by
        case p.payment_status
        when 'success' then 1
        when 'refunded' then 2
        when 'pending' then 3
        when 'failed' then 4
        else 5
        end, p.processed_at asc) as payment_rank

from payments p 
),
primary_payment as (
    select
        order_id,
        payment_id as primary_payment_id,
        payment_method as primary_payment_method,
        payment_status as primary_payment_status,
        payment_amount as primary_payment_amount,
        processed_at as primary_processed_at,
        gateway_ref as primary_gateway_ref,
        is_successful,
        is_refunded
    from
        payment_ranked
    qualify payment_rank = 1
),

payment_aggregates as (
    select 
        order_id,
        count(*) as total_payment_attempts,
        sum(case when is_successful then payment_amount else 0 end) as total_amount_collected,
        sum(case when is_refunded then payment_amount else 0 end) as total_amount_refunded,
        count(case when payment_status = 'failed' then 1 end) as failed_attempt_count,
        min(processed_at) as first_attempt_at,
        max(processed_at) as last_attempt_at,
        {# datediff between first and last payment #}
        datediff('minute',min(processed_at),max(case when is_successful then processed_at end)) as minutes_to_payment_success

    from 
        payments
    group by order_id

),
final as (
     select
        -- order context
        o.order_id,
        o.order_total,
        o.order_date,

        pp.primary_payment_id,
        pp.primary_payment_method,
        pp.primary_payment_status,
        pp.primary_payment_amount,
        pp.primary_processed_at,
        pp.is_successful  as payment_is_successful,
        pp.is_refunded  as payment_is_refunded,

        pa.total_payment_attempts,
        pa.total_amount_collected,
        pa.total_amount_refunded,
        pa.failed_attempt_count,
        pa.first_attempt_at,
        pa.last_attempt_at,
        pa.minutes_to_payment_success,

        --derived : net after refunds

        pa.total_amount_collected -pa.total_amount_refunded as net_amount_collected,

        --was payment collected in full 
        case
            when pa.total_amount_collected >=o.order_total then true 
            else false
            end as is_fully_paid,

        -- did it take multiple attempt

        case 
            when pa.total_payment_attempts >1 then true
            else false
            end as had_payment_retry,
        o._loaded_at

        from orders o
        left join primary_payment pp on o.order_id = pp.order_id
        left join payment_aggregates pa on o.order_id = pa.order_id
)

select * from final

