SELECT DISTINCT
    county_number,
    county,
FROM {{ ref('store_snapshot') }}
WHERE county_number IS NOT NULL AND CURRENT_TIMESTAMP > dbt_valid_from AND dbt_valid_to IS NULL