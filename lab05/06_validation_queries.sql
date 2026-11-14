-- Контрольные запросы после выполнения скриптов лабораторной 5.
SET search_path TO marketplace, public;

-- Сводная выручка продавца за период.
SELECT seller_revenue_for_period(
    1,
    TIMESTAMPTZ '2000-01-01 00:00:00+00',
    TIMESTAMPTZ '2100-01-01 00:00:00+00'
) AS seller_revenue;

-- Аудит смены цены.
SELECT product_id, old_price, new_price, changed_at, changed_by
FROM product_price_audit
ORDER BY id DESC
LIMIT 10;

-- Денормализованный рейтинг и среднее непосредственно по отзывам для сравнения.
SELECT
    p.id AS product_id,
    p.rating AS stored_rating,
    COALESCE(ROUND(AVG(r.score)::numeric, 2), 0) AS calculated_rating
FROM products AS p
LEFT JOIN reviews AS r ON r.product_id = p.id
GROUP BY p.id, p.rating
ORDER BY p.id
LIMIT 20;
