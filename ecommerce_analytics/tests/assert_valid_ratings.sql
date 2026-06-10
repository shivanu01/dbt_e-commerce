-- tests/assert_valid_ratings.sql
-- Business rule: ratings must be integers between 1 and 5 inclusive.
-- Values outside this range indicate source data quality issues.

SELECT
    review_id,
    product_id,
    customer_id,
    rating
FROM {{ ref('stg_reviews') }}
WHERE rating < 1
OR rating > 5
OR rating IS NULL