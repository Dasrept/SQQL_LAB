-- Таблица результата для lab02: приход, отгрузка и остаток по каждому товару.
-- Перед запуском выполните lab02/00_schema_from_lab01.sql и 01_seed_data.sql.

SET search_path TO marketplace, public;

SELECT
    p.id AS product_id,
    p.title AS product_name,
    COALESCE(SUM(m.quantity) FILTER (WHERE m.movement_type = 'received'), 0) AS received_qty,
    COALESCE(SUM(m.quantity) FILTER (WHERE m.movement_type = 'shipped'), 0) AS shipped_qty,
    s.quantity AS remaining_qty
FROM products AS p
JOIN stock AS s ON s.product_id = p.id
LEFT JOIN stock_movements AS m ON m.product_id = p.id
GROUP BY p.id, p.title, s.quantity
ORDER BY p.id;
