-- Лабораторная работа № 5. Функции и триггеры PostgreSQL.
-- Запускать после 00_schema_from_lab01.sql и 01_seed_data_from_lab02.sql.

SET search_path TO marketplace, public;

-- Средний рейтинг хранится в карточке товара как денормализованное поле.
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS rating NUMERIC(3, 2) NOT NULL DEFAULT 0
    CHECK (rating BETWEEN 0 AND 5);

-- Заполняем поле для отзывов, созданных до установки триггера.
UPDATE products AS p
SET rating = COALESCE(
    (
        SELECT ROUND(AVG(r.score)::numeric, 2)
        FROM reviews AS r
        WHERE r.product_id = p.id
    ),
    0
);

-- Историю цены сохраняем независимо от удаления карточки товара.
CREATE TABLE IF NOT EXISTS product_price_audit (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL,
    old_price  NUMERIC(12, 2) NOT NULL CHECK (old_price > 0),
    new_price  NUMERIC(12, 2) NOT NULL CHECK (new_price > 0),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_by TEXT NOT NULL DEFAULT session_user
);

-- Атомарно создаёт заказ и позицию и списывает остаток.
CREATE OR REPLACE FUNCTION place_order(
    p_user BIGINT,
    p_product BIGINT,
    p_qty INTEGER
)
RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = 'marketplace, public'
AS $$
DECLARE
    v_order_id BIGINT;
    v_price    NUMERIC(12, 2);
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Количество должно быть положительным';
    END IF;

    SELECT price
    INTO v_price
    FROM products
    WHERE id = p_product;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Товар % не найден', p_product;
    END IF;

    -- Условное атомарное списание защищает склад и при параллельных заказах.
    UPDATE stock
    SET quantity = quantity - p_qty,
        updated_at = now()
    WHERE product_id = p_product
      AND quantity >= p_qty;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Недостаточно товара на складе (id=%)', p_product;
    END IF;

    INSERT INTO orders (user_id, total_amount)
    VALUES (p_user, p_qty * v_price)
    RETURNING id INTO v_order_id;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product, p_qty, v_price);

    RETURN v_order_id;
END;
$$;

-- Возвращает выручку продавца за полуоткрытый интервал [p_from, p_to).
CREATE OR REPLACE FUNCTION seller_revenue_for_period(
    p_seller_id BIGINT,
    p_from TIMESTAMPTZ,
    p_to TIMESTAMPTZ
)
RETURNS NUMERIC(14, 2)
LANGUAGE plpgsql
STABLE
SET search_path = 'marketplace, public'
AS $$
DECLARE
    v_revenue NUMERIC(14, 2);
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from >= p_to THEN
        RAISE EXCEPTION 'Начало периода должно быть раньше его конца';
    END IF;

    SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0)::numeric(14, 2)
    INTO v_revenue
    FROM sellers AS s
    JOIN products AS p ON p.seller_id = s.id
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o ON o.id = oi.order_id
    WHERE s.id = p_seller_id
      AND o.status IN ('paid', 'processing', 'shipped', 'delivered')
      AND o.created_at >= p_from
      AND o.created_at < p_to;

    RETURN v_revenue;
END;
$$;

-- Триггерная функция сохраняет старую и новую цену только при реальном изменении.
CREATE OR REPLACE FUNCTION audit_product_price_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'marketplace, public'
AS $$
BEGIN
    IF OLD.price IS DISTINCT FROM NEW.price THEN
        INSERT INTO product_price_audit (product_id, old_price, new_price, changed_by)
        VALUES (OLD.id, OLD.price, NEW.price, session_user);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_price_audit ON products;
CREATE TRIGGER trg_products_price_audit
AFTER UPDATE OF price ON products
FOR EACH ROW
WHEN (OLD.price IS DISTINCT FROM NEW.price)
EXECUTE FUNCTION audit_product_price_change();

-- Пересчитывает сохранённый рейтинг по текущим отзывам.
CREATE OR REPLACE FUNCTION refresh_product_rating(p_product_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = 'marketplace, public'
AS $$
BEGIN
    UPDATE products AS p
    SET rating = COALESCE(
        (
            SELECT ROUND(AVG(r.score)::numeric, 2)
            FROM reviews AS r
            WHERE r.product_id = p_product_id
        ),
        0
    )
    WHERE p.id = p_product_id;
END;
$$;

-- Пересчитывает рейтинг после добавления, изменения или удаления отзыва.
CREATE OR REPLACE FUNCTION maintain_product_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'marketplace, public'
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM refresh_product_rating(NEW.product_id);
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM refresh_product_rating(OLD.product_id);
    ELSE
        PERFORM refresh_product_rating(OLD.product_id);
        IF NEW.product_id IS DISTINCT FROM OLD.product_id THEN
            PERFORM refresh_product_rating(NEW.product_id);
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_reviews_rating_after_insert ON reviews;
CREATE TRIGGER trg_reviews_rating_after_insert
AFTER INSERT ON reviews
FOR EACH ROW EXECUTE FUNCTION maintain_product_rating();

DROP TRIGGER IF EXISTS trg_reviews_rating_after_update ON reviews;
CREATE TRIGGER trg_reviews_rating_after_update
AFTER UPDATE OF score, product_id ON reviews
FOR EACH ROW EXECUTE FUNCTION maintain_product_rating();

DROP TRIGGER IF EXISTS trg_reviews_rating_after_delete ON reviews;
CREATE TRIGGER trg_reviews_rating_after_delete
AFTER DELETE ON reviews
FOR EACH ROW EXECUTE FUNCTION maintain_product_rating();
