{{config(materialized = 'table',description = 'Product master dimension. One row per product')}}

with products as (
    select  * from {{ref('stg_products')}}
),
product_sales as (
    select 
        product_id,
        count(distinct order_id) as times_ordered,
        sum(quantity) as total_units_sold,
        sum(line_total) as total_revenue,
        avg(unit_price) as avg_selling_price,
        min(unit_price) as min_selling_price,
        max(unit_price) as max_selling_price,
        sum(item_discount) as total_discounts_given,

    round(count( case when item_discount>0 then 1 end)*100.0/nullif(count(*),0),2) as pct_orders_discounted,


    from {{ref('stg_order_items')}}
    group by product_id
),
product_reviews as (
    Select 
        product_id,
        count(*) as review_count,
        round(avg(rating),2) as avg_rating,
        count(case when rating =5 then 1 end) as five_star_count,
        count(case when rating =1 then 1 end) as one_star_count,

        -- net promoter proxy: % 5-star minus % 1-star

        round(
            (count(case when rating =5 then 1 end)- count(case when rating = 1 then 1 end))*100.0
                    /nullif(count(*),0),2) as review_score  

    from {{ref('stg_reviews')}}
    group by product_id
),


final as (

    select
        p.product_id,
        p.product_name,
        p.category,
        p.subcategory,
        p.sku,
        p.is_active,
        p.created_at,

        p.cost_price,
        p.retail_price,
        p.gross_margin_pct,

        case 
            when p.retail_price>=100 then 'premium'
            when p.retail_price>=50 then 'mid_range'
            when p.retail_price>=20 then 'value'
            else 'budget'
        end as price_tier,

        coalesce(ps.times_ordered,0) as times_ordered,
        coalesce(ps.total_units_sold,0) as total_units_sold,
        coalesce(ps.total_revenue, 0)  as total_revenue,
        coalesce(ps.avg_selling_price,0) as avg_selling_price,
        coalesce(ps.total_discounts_given,0)  as total_discounts_given,
        coalesce(ps.pct_orders_discounted,0)  as pct_orders_discounted,

        round(coalesce(ps.total_revenue,0)-(p.cost_price)*coalesce(ps.total_units_sold,0),2) as total_gross_profit,

        case
            when coalesce(ps.total_revenue, 0) >= 1000 then 'hero'
            when coalesce(ps.total_revenue, 0) >= 500  then 'strong'
            when coalesce(ps.total_revenue, 0) >= 100  then 'average'
            when coalesce(ps.total_revenue, 0) > 0     then 'weak'
            else 'no_sales'
        end  as performance_tier,

        case 
            when ps.times_ordered is null then false else true end as has_been_ordered,

        coalesce(pr.review_count, 0) as review_count,
        pr.avg_rating,
        coalesce(pr.five_star_count, 0) as five_star_count,
        coalesce(pr.one_star_count, 0) as one_star_count,
        coalesce(pr.review_score, 0) as review_score,

        -- top rated = avg rating >= 4.5
        case
            when coalesce(pr.avg_rating, 0) >= 4.5 then true
            else false
        end  as is_top_rated,

        -- quality alert: selling well but rated poorly
        case
            when coalesce(ps.total_revenue,  0) >= 500
             and coalesce(pr.avg_rating,      0) < 3.0
            then true
            else false
        end  as has_quality_alert

    from 
    products p 
    left join product_sales ps on p.product_id = ps.product_id
    left join product_reviews pr on p.product_id = pr.product_id
)

select * from final