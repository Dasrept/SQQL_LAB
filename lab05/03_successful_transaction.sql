-- Демонстрация успешного оформления заказа в одной транзакции.
-- Перед запуском выполните файлы 00, 01 и 02.

SET search_path TO marketplace, public;

SELECT quantity AS stock_before_order FROM stock WHERE product_id = 2000;

BEGIN;

SELECT place_order(101, 2000, 1) AS created_order_id;

COMMIT;

-- Проверка результата: заказ, его позиция и уменьшенный складской остаток.
SELECT
    o.id AS order_id,
    o.user_id,
    o.total_amount,
    oi.product_id,
    oi.quantity AS ordered_quantity,
    s.quantity AS remaining_stock
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
JOIN stock AS s ON s.product_id = oi.product_id
WHERE o.id = (SELECT MAX(id) FROM orders)
ORDER BY oi.product_id;
