-- Лабораторная работа № 4. Оконные функции и аналитика.
-- Запускать после 00_schema_from_lab01.sql и 01_seed_data_from_lab02.sql.

SET search_path TO marketplace, public;

-- 1. ROW_NUMBER, RANK и DENSE_RANK: в категории «Электроника»
-- товары 1 и 13 имеют одинаковую максимальную цену.
SELECT
    c.name AS category_name,
    p.id AS product_id,
    p.title AS product_name,
    p.price,
    ROW_NUMBER() OVER w AS row_number_rank,
    RANK() OVER w AS rank_with_gaps,
    DENSE_RANK() OVER w AS dense_rank_without_gaps
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
WINDOW w AS (
    PARTITION BY p.category_id
    ORDER BY p.price DESC
)
ORDER BY c.name, p.price DESC, p.id
LIMIT 40;

-- 2. Три самых дорогих товара в каждой категории.
-- ROW_NUMBER гарантирует не более трёх строк на категорию;
-- id задаёт стабильный порядок при одинаковых ценах.
WITH ranked_products AS (
    SELECT
        c.name AS category_name,
        p.id AS product_id,
        p.title AS product_name,
        p.price,
        ROW_NUMBER() OVER (
            PARTITION BY p.category_id
            ORDER BY p.price DESC, p.id
        ) AS position_in_category
    FROM products AS p
    JOIN categories AS c ON c.id = p.category_id
)
SELECT category_name, product_id, product_name, price, position_in_category
FROM ranked_products
WHERE position_in_category <= 3
ORDER BY category_name, position_in_category;

-- 3. Выручка по дням и нарастающий итог.
-- В учебных данных заказы распределены по 30 календарным дням.
WITH daily_revenue AS (
    SELECT
        o.created_at::date AS sales_day,
        SUM(oi.quantity * oi.unit_price)::numeric(14, 2) AS revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    WHERE o.status IN ('paid', 'processing', 'shipped', 'delivered')
    GROUP BY o.created_at::date
)
SELECT
    sales_day,
    revenue,
    SUM(revenue) OVER (
        ORDER BY sales_day
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )::numeric(14, 2) AS running_revenue
FROM daily_revenue
ORDER BY sales_day;

-- 4. Доля выручки продавца внутри каждой категории.
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
    ) AS category_revenue_share_percent
FROM seller_category_revenue
ORDER BY category_name, revenue DESC, seller_id;

-- 5. LAG сравнивает день с предыдущим, LEAD показывает следующий день.
WITH daily_revenue AS (
    SELECT
        o.created_at::date AS sales_day,
        SUM(oi.quantity * oi.unit_price)::numeric(14, 2) AS revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    WHERE o.status IN ('paid', 'processing', 'shipped', 'delivered')
    GROUP BY o.created_at::date
),
neighboring_days AS (
    SELECT
        sales_day,
        revenue,
        LAG(revenue) OVER (ORDER BY sales_day) AS previous_day_revenue,
        LEAD(revenue) OVER (ORDER BY sales_day) AS next_day_revenue
    FROM daily_revenue
)
SELECT
    sales_day,
    revenue,
    previous_day_revenue,
    revenue - previous_day_revenue AS change_from_previous_day,
    next_day_revenue,
    next_day_revenue - revenue AS change_to_next_day
FROM neighboring_days
ORDER BY sales_day;
