-- Демонстрация аудита цены и автоматического пересчёта рейтинга.
-- Перед запуском выполните файлы 00, 01 и 02.

SET search_path TO marketplace, public;

-- Смена цены создаёт строку с прежним и новым значением.
UPDATE products
SET price = price + 1.00
WHERE id = 1500;

SELECT id, product_id, old_price, new_price, changed_at, changed_by
FROM product_price_audit
WHERE product_id = 1500
ORDER BY id DESC
LIMIT 5;

-- У товара 1500 ещё нет исходного отзыва; INSERT/UPDATE безопасен при повторном запуске.
INSERT INTO reviews (user_id, product_id, score, comment)
VALUES (101, 1500, 5, 'Демонстрационный отзыв для проверки триггера рейтинга')
ON CONFLICT (user_id, product_id)
DO UPDATE SET score = EXCLUDED.score,
              comment = EXCLUDED.comment;

SELECT id AS product_id, title, rating
FROM products
WHERE id = 1500;
