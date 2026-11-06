-- Лабораторная работа № 2: выборка и фильтрация.
-- Перед выполнением запустите 01_seed_data.sql.

SET search_path TO marketplace, public;

-- 1. Различные сочетания категории и активности с псевдонимами.
SELECT DISTINCT
    category_id AS category,
    is_active AS active
FROM products
ORDER BY category, active;

-- 2. Несколько условий с AND и OR; скобки задают порядок объединения.
SELECT id, title, price, category_id
FROM products
WHERE is_active = TRUE
  AND (price BETWEEN 1500 AND 2500 OR category_id IN (
      SELECT id FROM categories WHERE name IN ('Телефоны', 'Книги')
  ))
ORDER BY id
LIMIT 25;

-- 3. Поиск телефона без описания: ILIKE не учитывает регистр, IS NULL ищет пустые значения.
SELECT
    id,
    title AS product_name,
    COALESCE(description, 'нет описания') AS description,
    price
FROM products
WHERE title ILIKE '%телефон%'
  AND description IS NULL
ORDER BY id
LIMIT 20;

-- 4. BETWEEN задаёт включённый диапазон цены, IN проверяет список категорий.
SELECT id, title, price, category_id
FROM products
WHERE price BETWEEN 1000 AND 2000
  AND category_id IN (
      SELECT id FROM categories WHERE name IN ('Электроника', 'Телефоны', 'Книги')
  )
ORDER BY price ASC, title ASC
LIMIT 30;

-- 5. Сортировка по двум столбцам в разных направлениях.
SELECT id, title, price
FROM products
WHERE is_active = TRUE
ORDER BY price DESC, title ASC
LIMIT 30;

-- 6. Вторая страница по 20 товаров: первые 20 пропускаются.
SELECT id, title, price
FROM products
ORDER BY id
LIMIT 20 OFFSET 20;
