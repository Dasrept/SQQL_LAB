-- Лабораторная работа № 1. Схема маркетплейса по логической модели задания.
-- PostgreSQL 15+. Повторный запуск удаляет и пересоздаёт схему marketplace.
-- ВАЖНО: перед запуском сохраните нужные данные схемы marketplace.

BEGIN;
DROP SCHEMA IF EXISTS marketplace CASCADE;
CREATE SCHEMA marketplace;
SET search_path TO marketplace, public;

CREATE TABLE users (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name  TEXT NOT NULL,
    email      TEXT NOT NULL UNIQUE,
    phone      TEXT UNIQUE,
    role       TEXT NOT NULL DEFAULT 'customer'
               CHECK (role IN ('customer', 'seller', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_email_format CHECK (position('@' IN email) > 1)
);

CREATE TABLE sellers (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL UNIQUE REFERENCES users(id)
                ON DELETE RESTRICT ON UPDATE CASCADE,
    store_name  TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE categories (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id BIGINT REFERENCES categories(id)
              ON DELETE RESTRICT ON UPDATE CASCADE,
    name      TEXT NOT NULL UNIQUE,
    CONSTRAINT categories_not_own_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE TABLE products (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id   BIGINT NOT NULL REFERENCES sellers(id)
                ON DELETE RESTRICT ON UPDATE CASCADE,
    category_id BIGINT NOT NULL REFERENCES categories(id)
                ON DELETE RESTRICT ON UPDATE CASCADE,
    title       TEXT NOT NULL,
    description TEXT,
    price       NUMERIC(12, 2) NOT NULL CHECK (price > 0),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Остаток отделён от карточки товара; одна строка на товар.
CREATE TABLE stock (
    product_id BIGINT PRIMARY KEY REFERENCES products(id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    quantity   INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE carts (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL UNIQUE REFERENCES users(id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ассоциативная таблица корзин и товаров: связь M:N.
CREATE TABLE cart_items (
    cart_id    BIGINT NOT NULL REFERENCES carts(id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id)
               ON DELETE RESTRICT ON UPDATE CASCADE,
    quantity   INTEGER NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (cart_id, product_id)
);

CREATE TABLE orders (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users(id)
                 ON DELETE RESTRICT ON UPDATE CASCADE,
    status       TEXT NOT NULL DEFAULT 'new'
                 CHECK (status IN ('new', 'paid', 'processing', 'shipped', 'delivered', 'cancelled')),
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, user_id)
);

-- Снимок цены хранится в строке заказа, чтобы история не менялась при смене цены товара.
CREATE TABLE order_items (
    order_id   BIGINT NOT NULL REFERENCES orders(id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id)
               ON DELETE RESTRICT ON UPDATE CASCADE,
    quantity   INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE payments (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id   BIGINT NOT NULL REFERENCES orders(id)
               ON DELETE RESTRICT ON UPDATE CASCADE,
    amount     NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    status     TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
    paid_at    TIMESTAMPTZ
);

CREATE TABLE addresses (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id   BIGINT NOT NULL REFERENCES users(id)
              ON DELETE CASCADE ON UPDATE CASCADE,
    city      TEXT NOT NULL,
    street    TEXT NOT NULL,
    house     TEXT NOT NULL,
    apartment TEXT,
    UNIQUE (id, user_id)
);

CREATE TABLE deliveries (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id        BIGINT NOT NULL UNIQUE REFERENCES orders(id)
                    ON DELETE CASCADE ON UPDATE CASCADE,
    address_id      BIGINT NOT NULL REFERENCES addresses(id)
                    ON DELETE RESTRICT ON UPDATE CASCADE,
    delivery_status TEXT NOT NULL DEFAULT 'created'
                    CHECK (delivery_status IN ('created', 'shipped', 'delivered', 'returned')),
    delivery_date   TIMESTAMPTZ
);

CREATE TABLE reviews (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users(id)
               ON DELETE RESTRICT ON UPDATE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    score      SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment    TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, product_id)
);

CREATE INDEX products_seller_idx ON products(seller_id);
CREATE INDEX products_category_idx ON products(category_id);
CREATE INDEX orders_user_created_idx ON orders(user_id, created_at DESC);
CREATE INDEX order_items_product_idx ON order_items(product_id);
CREATE INDEX reviews_product_created_idx ON reviews(product_id, created_at DESC);
CREATE INDEX deliveries_address_idx ON deliveries(address_id);

-- Запрещаем цикл в дереве категорий.
CREATE FUNCTION prevent_category_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.parent_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        WITH RECURSIVE ancestors(id, parent_id) AS (
            SELECT id, parent_id FROM categories WHERE id = NEW.parent_id
            UNION ALL
            SELECT c.id, c.parent_id
            FROM categories AS c
            JOIN ancestors AS a ON c.id = a.parent_id
            WHERE a.parent_id IS NOT NULL
        )
        SELECT 1 FROM ancestors WHERE id = NEW.id
    ) THEN
        RAISE EXCEPTION 'Изменение создаёт цикл в дереве категорий';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER categories_prevent_cycle
BEFORE INSERT OR UPDATE OF parent_id ON categories
FOR EACH ROW EXECUTE FUNCTION prevent_category_cycle();

-- Заказ обязан содержать хотя бы одну позицию к моменту COMMIT.
CREATE FUNCTION assert_order_has_items(p_order_id BIGINT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM orders WHERE id = p_order_id)
       AND NOT EXISTS (SELECT 1 FROM order_items WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'Заказ % должен содержать хотя бы одну позицию', p_order_id;
    END IF;
END;
$$;

CREATE FUNCTION check_order_items_deferred()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_TABLE_NAME = 'orders' THEN
        PERFORM assert_order_has_items(NEW.id);
    ELSE
        IF TG_OP <> 'INSERT' THEN
            PERFORM assert_order_has_items(OLD.order_id);
        END IF;
        IF TG_OP <> 'DELETE' THEN
            PERFORM assert_order_has_items(NEW.order_id);
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER orders_require_item
AFTER INSERT OR UPDATE ON orders
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_items_deferred();

CREATE CONSTRAINT TRIGGER order_items_keep_order_nonempty
AFTER INSERT OR UPDATE OR DELETE ON order_items
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_items_deferred();

COMMIT;
