-- Лабораторная работа № 2: повторяемое заполнение учебной схемы.
-- Скрипт очищает таблицы marketplace, сбрасывает ID и создаёт согласованный набор данных.
-- Запускать после 00_schema_from_lab01.sql в PostgreSQL 15+.

BEGIN;
SET search_path TO marketplace, public;

-- Обычная таблица операций прихода и отгрузки товара для складской сводки.
CREATE TABLE IF NOT EXISTS stock_movements (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id    BIGINT NOT NULL REFERENCES products(id)
                  ON DELETE CASCADE ON UPDATE CASCADE,
    movement_type TEXT NOT NULL CHECK (movement_type IN ('received', 'shipped')),
    quantity      INTEGER NOT NULL CHECK (quantity > 0),
    moved_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

TRUNCATE TABLE
    stock_movements,
    reviews,
    deliveries,
    addresses,
    payments,
    order_items,
    orders,
    cart_items,
    carts,
    stock,
    products,
    sellers,
    categories,
    users
RESTART IDENTITY CASCADE;

-- 1 000 пользователей: первые 100 также имеют профили продавцов.
INSERT INTO users (full_name, email, phone, role)
SELECT
    'Пользователь ' || g.n,
    'user' || g.n || '@example.test',
    '+7000' || lpad(g.n::text, 7, '0'),
    CASE WHEN g.n <= 100 THEN 'seller' ELSE 'customer' END
FROM generate_series(1, 1000) AS g(n)
ORDER BY g.n;

INSERT INTO sellers (user_id, store_name, description)
SELECT id, 'Магазин ' || id, 'Тестовый продавец №' || id
FROM users
WHERE role = 'seller'
ORDER BY id;

-- Корневые категории и дочерние категории для проверки иерархии.
INSERT INTO categories (name)
VALUES ('Электроника'), ('Книги'), ('Одежда');

INSERT INTO categories (parent_id, name)
SELECT parent.id, child.name
FROM (VALUES
    ('Электроника', 'Телефоны'),
    ('Электроника', 'Компьютеры'),
    ('Электроника', 'Аксессуары'),
    ('Книги', 'Художественная литература'),
    ('Книги', 'Учебники'),
    ('Книги', 'Детские книги'),
    ('Одежда', 'Мужская одежда'),
    ('Одежда', 'Женская одежда'),
    ('Одежда', 'Обувь')
) AS child(parent_name, name)
JOIN categories AS parent ON parent.name = child.parent_name
ORDER BY parent.id, child.name;

-- 2 000 товаров: данные продавцов и категорий выбираются циклически.
INSERT INTO products (seller_id, category_id, title, description, price, is_active)
SELECT
    seller.id,
    category.id,
    CASE WHEN g.n % 5 = 0
         THEN 'Телефон модель ' || g.n
         ELSE 'Товар модель ' || g.n
    END,
    CASE WHEN g.n % 10 = 0
         THEN NULL
         ELSE 'Описание тестового товара №' || g.n
    END,
    (1000 + ((g.n * 137) % 400000) / 100.0)::numeric(12, 2),
    g.n % 20 <> 0
FROM generate_series(1, 2000) AS g(n)
CROSS JOIN LATERAL (
    SELECT id FROM sellers ORDER BY id
    OFFSET ((g.n - 1) % 100) LIMIT 1
) AS seller
CROSS JOIN LATERAL (
    SELECT id FROM categories ORDER BY id
    OFFSET ((g.n - 1) % 12) LIMIT 1
) AS category
ORDER BY g.n;

INSERT INTO stock (product_id, quantity)
SELECT id, (id * 7) % 100
FROM products
ORDER BY id;

-- Два движения на каждый товар: поступление и отгрузка.
INSERT INTO stock_movements (product_id, movement_type, quantity, moved_at)
SELECT p.id, 'received', 50 + (p.id % 100), now() - interval '30 days'
FROM products AS p
UNION ALL
SELECT p.id, 'shipped', 1 + (p.id % 40), now() - interval '1 day'
FROM products AS p;

-- Текущий остаток равен поступлениям минус отгрузки.
UPDATE stock AS s
SET quantity = totals.remaining_quantity,
    updated_at = now()
FROM (
    SELECT
        product_id,
        SUM(CASE movement_type
                WHEN 'received' THEN quantity
                WHEN 'shipped' THEN -quantity
            END)::integer AS remaining_quantity
    FROM stock_movements
    GROUP BY product_id
) AS totals
WHERE totals.product_id = s.product_id;

-- Адреса покупателей (пользователи 101–1 000).
INSERT INTO addresses (user_id, city, street, house, apartment)
SELECT
    u.id,
    CASE u.id % 3
        WHEN 0 THEN 'Москва'
        WHEN 1 THEN 'Казань'
        ELSE 'Новосибирск'
    END,
    'Улица ' || u.id,
    (1 + u.id % 150)::text,
    CASE WHEN u.id % 4 = 0 THEN NULL ELSE (1 + u.id % 200)::text END
FROM users AS u
WHERE u.role = 'customer'
ORDER BY u.id;

-- Корзины для первых 200 покупателей и по три позиции в каждой.
INSERT INTO carts (user_id)
SELECT id FROM users WHERE id BETWEEN 101 AND 300 ORDER BY id;

INSERT INTO cart_items (cart_id, product_id, quantity)
SELECT c.id, ((c.id * 3 + item.item_no) % 2000) + 1, 1 + (c.id + item.item_no) % 5
FROM carts AS c
CROSS JOIN (VALUES (1), (2), (3)) AS item(item_no)
ORDER BY c.id, item.item_no;

-- 1 500 заказов, то есть требование «не менее 1 000» выполнено.
INSERT INTO orders (user_id, status, total_amount)
SELECT
    101 + ((g.n - 1) % 900),
    CASE g.n % 6
        WHEN 0 THEN 'cancelled'
        WHEN 1 THEN 'new'
        WHEN 2 THEN 'paid'
        WHEN 3 THEN 'processing'
        WHEN 4 THEN 'shipped'
        ELSE 'delivered'
    END,
    0
FROM generate_series(1, 1500) AS g(n)
ORDER BY g.n;

-- По две позиции в заказе; цена берётся из карточки товара на момент генерации.
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    o.id,
    p.id,
    1 + (o.id + item.item_no) % 4,
    p.price
FROM orders AS o
CROSS JOIN (VALUES (1), (2)) AS item(item_no)
JOIN products AS p
  ON p.id = ((o.id * 2 + item.item_no - 2) % 2000) + 1
ORDER BY o.id, item.item_no;

-- Обновляем сумму заказа на сумму его позиций.
UPDATE orders AS o
SET total_amount = totals.amount
FROM (
    SELECT order_id, SUM(quantity * unit_price) AS amount
    FROM order_items
    GROUP BY order_id
) AS totals
WHERE totals.order_id = o.id;

-- Платежи создаются для части заказов; остальные остаются без платежа.
INSERT INTO payments (order_id, amount, status, paid_at)
SELECT
    o.id,
    o.total_amount,
    CASE o.id % 3
        WHEN 0 THEN 'failed'
        WHEN 1 THEN 'succeeded'
        ELSE 'pending'
    END,
    CASE WHEN o.id % 3 = 1 THEN o.created_at + interval '1 hour' ELSE NULL END
FROM orders AS o
WHERE o.id % 2 = 0
ORDER BY o.id;

-- Доставка связывает заказ с адресом того же покупателя.
INSERT INTO deliveries (order_id, address_id, delivery_status, delivery_date)
SELECT
    o.id,
    a.id,
    CASE o.id % 3
        WHEN 0 THEN 'created'
        WHEN 1 THEN 'shipped'
        ELSE 'delivered'
    END,
    CASE WHEN o.id % 3 = 2 THEN o.created_at + interval '3 days' ELSE NULL END
FROM orders AS o
JOIN addresses AS a ON a.user_id = o.user_id
WHERE o.id % 4 = 0
  AND o.status <> 'cancelled'
ORDER BY o.id;

-- Отзывы для первых 1 000 товаров; у остальных товары останутся без отзывов.
INSERT INTO reviews (user_id, product_id, score, comment)
SELECT
    101 + ((p.id - 1) % 900),
    p.id,
    1 + p.id % 5,
    'Тестовый отзыв на товар №' || p.id
FROM products AS p
WHERE p.id <= 1000
ORDER BY p.id;

COMMIT;
