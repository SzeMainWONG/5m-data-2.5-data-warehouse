SELECT DISTINCT
    category,
    category_name
FROM {{ ref('item_snapshot') }}
WHERE category IS NOT NULL AND CURRENT_TIMESTAMP > dbt_valid_from AND dbt_valid_to IS NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY category ORDER BY dbt_valid_from DESC) = 1