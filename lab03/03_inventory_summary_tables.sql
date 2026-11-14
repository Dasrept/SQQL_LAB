-- Таблицы результатов для lab03: движения товаров и остатки по продавцам.
-- Сначала выполните 00_schema_from_lab01.sql,
-- 01_seed_data_from_lab02.sql и 02_joins_analytics_views.sql.

SET search_path TO marketplace, public;

-- Приход, отгрузка и текущий остаток по каждому товару.
SELECT
    product_id,
    product_name,
    received_qty,
    shipped_qty,
    remaining_qty
FROM v_inventory_movement_summary
ORDER BY product_id
LIMIT 25;

-- Суммарное количество товаров по каждому продавцу.
SELECT
    seller_id,
    store_name,
    products_count,
    received_qty,
    shipped_qty,
    remaining_qty
FROM v_inventory_by_seller
ORDER BY remaining_qty DESC
LIMIT 25;
