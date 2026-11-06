-- Лабораторная работа № 3: JOIN, агрегаты, подзапросы, CTE и представления.
-- Перед выполнением запустите lab01/01_schema.sql и lab02/01_seed_data.sql.

SET search_path TO marketplace, public;

-- 1. INNER JOIN трёх таблиц: товар, категория и продавец.
SELECT
    p.id AS product_id,
    p.title AS product_name,
    c.name AS category_name,
    s.store_name AS seller_name,
    p.price
FROM products AS p
INNER JOIN categories AS c ON c.id = p.category_id
INNER JOIN sellers AS s ON s.id = p.seller_id
ORDER BY p.id
LIMIT 25;

-- 2. LEFT JOIN: товары, у которых ещё нет отзывов.
SELECT
    p.id AS product_id,
    p.title AS product_name,
    p.price
FROM products AS p
LEFT JOIN reviews AS r ON r.product_id = p.id
WHERE r.id IS NULL
ORDER BY p.id
LIMIT 25;

-- 3. Количество товаров и средняя цена по каждой категории.
SELECT
    c.id AS category_id,
    c.name AS category_name,
    COUNT(p.id) AS products_count,
    ROUND(AVG(p.price), 2) AS average_price
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.id
GROUP BY c.id, c.name
ORDER BY products_count DESC, c.name ASC;

-- 4. Выручка по продавцам с фильтрацией сгруппированных результатов через HAVING.
SELECT
    s.id AS seller_id,
    s.store_name,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM sellers AS s
JOIN products AS p ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
JOIN orders AS o ON o.id = oi.order_id
WHERE o.status IN ('paid', 'processing', 'shipped', 'delivered')
GROUP BY s.id, s.store_name
HAVING SUM(oi.quantity * oi.unit_price) > 10000
ORDER BY revenue DESC;

-- 5. Скалярный подзапрос: товары дороже средней цены всех товаров.
SELECT id, title, price
FROM products
WHERE price > (SELECT AVG(price) FROM products)
ORDER BY price DESC, id
LIMIT 25;

-- 6. Подзапрос с IN: товары из дочерних категорий.
SELECT p.id, p.title, p.category_id
FROM products AS p
WHERE p.category_id IN (
    SELECT c.id
    FROM categories AS c
    WHERE c.parent_id IS NOT NULL
)
ORDER BY p.id
LIMIT 25;

-- 7. Коррелированный подзапрос с EXISTS: продавцы хотя бы с одним активным товаром.
SELECT s.id, s.store_name
FROM sellers AS s
WHERE EXISTS (
    SELECT 1
    FROM products AS p
    WHERE p.seller_id = s.id
      AND p.is_active = TRUE
)
ORDER BY s.id
LIMIT 25;

-- 8. CTE: сначала считаем выручку каждого продавца, затем долю в общей выручке.
WITH seller_revenue AS (
    SELECT
        s.id AS seller_id,
        s.store_name,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM sellers AS s
    JOIN products AS p ON p.seller_id = s.id
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o ON o.id = oi.order_id
    WHERE o.status IN ('paid', 'processing', 'shipped', 'delivered')
    GROUP BY s.id, s.store_name
),
revenue_with_share AS (
    SELECT
        seller_id,
        store_name,
        revenue,
        revenue / NULLIF(SUM(revenue) OVER (), 0) AS revenue_share
    FROM seller_revenue
)
SELECT seller_id, store_name, revenue, revenue_share
FROM revenue_with_share
ORDER BY revenue DESC;

-- 9. Рекурсивный CTE: дерево категорий с глубиной и путём от корня.
WITH RECURSIVE category_tree AS (
    SELECT
        id,
        parent_id,
        name,
        0 AS depth,
        ARRAY[id] AS path
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    SELECT
        child.id,
        child.parent_id,
        child.name,
        parent.depth + 1,
        parent.path || child.id
    FROM categories AS child
    JOIN category_tree AS parent ON child.parent_id = parent.id
    WHERE NOT (child.id = ANY(parent.path))
)
SELECT id, parent_id, repeat('  ', depth) || name AS category_tree, depth
FROM category_tree
ORDER BY path;

-- 10. Представление-каталог: готовое соединение товаров, категорий и продавцов.
CREATE OR REPLACE VIEW v_product_catalog AS
SELECT
    p.id AS product_id,
    p.title AS product_name,
    c.name AS category_name,
    s.store_name AS seller_name,
    p.price,
    p.is_active
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers AS s ON s.id = p.seller_id;

-- 11. Представление со статистикой категорий, включая категории без товаров.
CREATE OR REPLACE VIEW v_category_statistics AS
SELECT
    c.id AS category_id,
    c.name AS category_name,
    COUNT(p.id) AS products_count,
    ROUND(AVG(p.price), 2) AS average_price
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.id
GROUP BY c.id, c.name;

-- 12. Представление с выручкой продавцов по оплаченным и исполняемым заказам.
CREATE OR REPLACE VIEW v_seller_revenue AS
SELECT
    s.id AS seller_id,
    s.store_name,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM sellers AS s
JOIN products AS p ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
JOIN orders AS o ON o.id = oi.order_id
WHERE o.status IN ('paid', 'processing', 'shipped', 'delivered')
GROUP BY s.id, s.store_name;

-- Примеры обращения к созданным представлениям.
SELECT * FROM v_product_catalog ORDER BY product_id LIMIT 20;
SELECT * FROM v_category_statistics ORDER BY products_count DESC, category_name;
SELECT * FROM v_seller_revenue ORDER BY revenue DESC LIMIT 20;
