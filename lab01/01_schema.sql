-- Лабораторная работа № 1. Структура базы данных маркетплейса.
-- Повторный запуск пересоздаёт схему marketplace с нуля.
-- ВАЖНО: DROP SCHEMA удалит предыдущие данные этой учебной схемы.

BEGIN;
DROP SCHEMA IF EXISTS marketplace CASCADE;
CREATE SCHEMA marketplace;
SET search_path TO marketplace, public;

CREATE TABLE users (
    user_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    full_name     TEXT NOT NULL,
    phone         TEXT UNIQUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_email_format CHECK (position('@' IN email) > 1)
);

CREATE TABLE seller_profiles (
    seller_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT NOT NULL UNIQUE REFERENCES users(user_id)
                 ON DELETE RESTRICT ON UPDATE CASCADE,
    display_name TEXT NOT NULL UNIQUE,
    legal_name   TEXT NOT NULL,
    tax_number   TEXT NOT NULL UNIQUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE addresses (
    address_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(user_id)
                ON DELETE CASCADE ON UPDATE CASCADE,
    country     TEXT NOT NULL,
    city        TEXT NOT NULL,
    street      TEXT NOT NULL,
    postal_code TEXT NOT NULL,
    is_default  BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (address_id, user_id)
);

CREATE TABLE categories (
    category_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_category_id BIGINT REFERENCES categories(category_id)
                       ON DELETE RESTRICT ON UPDATE CASCADE,
    name               TEXT NOT NULL UNIQUE,
    description        TEXT,
    CONSTRAINT categories_not_own_parent
        CHECK (parent_category_id IS NULL OR parent_category_id <> category_id)
);

CREATE TABLE products (
    product_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id   BIGINT NOT NULL REFERENCES seller_profiles(seller_id)
                ON DELETE RESTRICT ON UPDATE CASCADE,
    category_id BIGINT NOT NULL REFERENCES categories(category_id)
                ON DELETE RESTRICT ON UPDATE CASCADE,
    title       TEXT NOT NULL,
    description TEXT,
    price       NUMERIC(12, 2) NOT NULL CHECK (price > 0),
    stock_qty   INTEGER NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE product_images (
    image_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL REFERENCES products(product_id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    image_url  TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    UNIQUE (product_id, image_url)
);

CREATE TABLE customer_orders (
    order_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    buyer_id        BIGINT NOT NULL REFERENCES users(user_id)
                    ON DELETE RESTRICT ON UPDATE CASCADE,
    shipping_address_id BIGINT,
    -- Если адрес указан, его владелец должен совпадать с покупателем.
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled')),
    placed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT orders_address_belongs_to_buyer
        FOREIGN KEY (shipping_address_id, buyer_id)
        REFERENCES addresses(address_id, user_id)
        ON DELETE SET NULL (shipping_address_id) ON UPDATE CASCADE
);

CREATE TABLE order_items (
    order_id   BIGINT NOT NULL REFERENCES customer_orders(order_id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(product_id)
               ON DELETE RESTRICT ON UPDATE CASCADE,
    quantity   INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id   BIGINT NOT NULL UNIQUE REFERENCES customer_orders(order_id)
               ON DELETE RESTRICT ON UPDATE CASCADE,
    amount     NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    method     TEXT NOT NULL CHECK (method IN ('card', 'sbp', 'cash')),
    status     TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
    paid_at    TIMESTAMPTZ
);

CREATE TABLE reviews (
    review_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL REFERENCES products(product_id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    author_id  BIGINT NOT NULL REFERENCES users(user_id)
               ON DELETE RESTRICT ON UPDATE CASCADE,
    rating     SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (product_id, author_id)
);

CREATE TABLE tags (
    tag_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name   TEXT NOT NULL UNIQUE
);

CREATE TABLE product_tags (
    product_id BIGINT NOT NULL REFERENCES products(product_id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    tag_id     BIGINT NOT NULL REFERENCES tags(tag_id)
               ON DELETE CASCADE ON UPDATE CASCADE,
    PRIMARY KEY (product_id, tag_id)
);

CREATE TABLE wishlists (
    wishlist_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(user_id)
                ON DELETE CASCADE ON UPDATE CASCADE,
    name        TEXT NOT NULL DEFAULT 'Избранное',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, name)
);

CREATE TABLE wishlist_items (
    wishlist_id BIGINT NOT NULL REFERENCES wishlists(wishlist_id)
                ON DELETE CASCADE ON UPDATE CASCADE,
    product_id  BIGINT NOT NULL REFERENCES products(product_id)
                ON DELETE CASCADE ON UPDATE CASCADE,
    added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (wishlist_id, product_id)
);

-- У одного пользователя может быть не более одного адреса по умолчанию.
CREATE UNIQUE INDEX addresses_one_default_per_user_idx
    ON addresses(user_id) WHERE is_default;

CREATE INDEX products_category_idx ON products(category_id);
CREATE INDEX products_seller_idx ON products(seller_id);
CREATE INDEX orders_buyer_placed_idx ON customer_orders(buyer_id, placed_at DESC);
CREATE INDEX reviews_product_created_idx ON reviews(product_id, created_at DESC);

-- Не допускаем циклы в дереве категорий, включая прямую ссылку на себя.
CREATE FUNCTION prevent_category_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.parent_category_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.parent_category_id = NEW.category_id THEN
        RAISE EXCEPTION 'Категория не может быть родителем самой себе';
    END IF;

    IF EXISTS (
        WITH RECURSIVE ancestors(category_id, parent_category_id) AS (
            SELECT category_id, parent_category_id
            FROM categories
            WHERE category_id = NEW.parent_category_id
          UNION ALL
            SELECT c.category_id, c.parent_category_id
            FROM categories AS c
            JOIN ancestors AS a ON c.category_id = a.parent_category_id
            WHERE a.parent_category_id IS NOT NULL
        )
        SELECT 1 FROM ancestors WHERE category_id = NEW.category_id
    ) THEN
        RAISE EXCEPTION 'Изменение создаёт цикл в дереве категорий';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER categories_prevent_cycle
BEFORE INSERT OR UPDATE OF parent_category_id ON categories
FOR EACH ROW EXECUTE FUNCTION prevent_category_cycle();

-- Заказ должен содержать хотя бы одну позицию к моменту COMMIT.
-- Отложенная проверка позволяет вставить заказ и позиции одной транзакцией.
CREATE FUNCTION assert_order_has_items(p_order_id BIGINT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM customer_orders WHERE order_id = p_order_id)
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
    IF TG_TABLE_NAME = 'customer_orders' THEN
        PERFORM assert_order_has_items(NEW.order_id);
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

CREATE CONSTRAINT TRIGGER customer_orders_require_item
AFTER INSERT OR UPDATE ON customer_orders
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_items_deferred();

CREATE CONSTRAINT TRIGGER order_items_keep_order_nonempty
AFTER INSERT OR UPDATE OR DELETE ON order_items
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_items_deferred();

COMMIT;
