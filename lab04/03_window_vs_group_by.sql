-- Лабораторная работа № 4. Два способа вычислить долю продавца в категории.
-- Оба запроса используют один и тот же набор данных и фильтр заказов.

SET search_path TO marketplace, public;

-- Способ 1: оконная SUM сохраняет строки продавцов и добавляет итог категории.
WITH seller_category_revenue AS (
    SELECT
        p.category_id,
        c.name AS category_name,
        s.id AS seller_id,
        s.store_name,
        SUM(oi.quantity * oi.unit_price)::numeric(14, 2) AS revenue
    FROM sellers AS s
    JOIN products AS p ON p.seller_id = s.id
    JOIN categories AS c ON c.id = p.category_id
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o ON o.id = oi.order_id
    WHERE o.status IN ('paid', 'processing', 'shipped', 'delivered')
    GROUP BY p.category_id, c.name, s.id, s.store_name
)
SELECT
    category_name,
    seller_id,
    store_name,
    revenue,
    ROUND(
        100 * revenue / NULLIF(SUM(revenue) OVER (PARTITION BY category_id), 0),
        2
    ) AS category_share_percent
FROM seller_category_revenue
ORDER BY category_name, revenue DESC, seller_id;

-- Способ 2: обычная группировка строит итоги отдельно, затем они соединяются.
WITH seller_category_revenue AS (
    SELECT
        p.category_id,
        c.name AS category_name,
        s.id AS seller_id,
        s.store_name,
        SUM(oi.quantity * oi.unit_price)::numeric(14, 2) AS revenue
    FROM sellers AS s
    JOIN products AS p ON p.seller_id = s.id
    JOIN categories AS c ON c.id = p.category_id
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o ON o.id = oi.order_id
    WHERE o.status IN ('paid', 'processing', 'shipped', 'delivered')
    GROUP BY p.category_id, c.name, s.id, s.store_name
),
category_revenue AS (
    SELECT category_id, SUM(revenue) AS total_revenue
    FROM seller_category_revenue
    GROUP BY category_id
)
SELECT
    scr.category_name,
    scr.seller_id,
    scr.store_name,
    scr.revenue,
    ROUND(100 * scr.revenue / NULLIF(cr.total_revenue, 0), 2) AS category_share_percent
FROM seller_category_revenue AS scr
JOIN category_revenue AS cr ON cr.category_id = scr.category_id
ORDER BY scr.category_name, scr.revenue DESC, scr.seller_id;
