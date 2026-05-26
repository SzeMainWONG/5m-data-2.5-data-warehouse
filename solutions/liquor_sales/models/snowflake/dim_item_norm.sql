SELECT
    item_number,
    item_description,
    category,
    vendor_number,
    pack,
    bottle_volume_ml
FROM {{ ref('item_snapshot') }}
WHERE CURRENT_TIMESTAMP > dbt_valid_from and dbt_valid_to IS NULL