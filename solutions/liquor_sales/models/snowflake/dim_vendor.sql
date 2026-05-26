SELECT DISTINCT
    vendor_number,
    vendor_name
FROM {{ ref('item_snapshot') }}
WHERE vendor_number IS NOT NULL AND CURRENT_TIMESTAMP > dbt_valid_from AND dbt_valid_to IS NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY vendor_number ORDER BY dbt_valid_from DESC) = 1