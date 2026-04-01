-- ============================================
-- SportData: Seed Data
-- ============================================

-- Marketplaces
INSERT INTO marketplaces (slug, name, api_base_url) VALUES
  ('wildberries', 'Wildberries', 'https://statistics-api.wildberries.ru'),
  ('ozon', 'Ozon', 'https://api-seller.ozon.ru'),
  ('yandex_market', 'Яндекс Маркет', 'https://api.partner.market.yandex.ru')
ON CONFLICT (slug) DO NOTHING;

-- Categories
INSERT INTO categories (slug, name) VALUES
  ('running', 'Бег'),
  ('fitness', 'Фитнес'),
  ('swimming', 'Плавание'),
  ('team_sports', 'Командные виды'),
  ('outdoor', 'Туризм'),
  ('accessories', 'Аксессуары')
ON CONFLICT (slug) DO NOTHING;

-- Products (30 items)
INSERT INTO products (name, sku, barcode, cost_price, category_id) VALUES
  ('Кроссовки беговые Pro Air', 'RUN-001', '4600001000011', 2800, (SELECT id FROM categories WHERE slug='running')),
  ('Кроссовки беговые Lite', 'RUN-002', '4600001000028', 1900, (SELECT id FROM categories WHERE slug='running')),
  ('Шорты беговые DryFit', 'RUN-003', '4600001000035', 450, (SELECT id FROM categories WHERE slug='running')),
  ('Футболка беговая CoolMax', 'RUN-004', '4600001000042', 380, (SELECT id FROM categories WHERE slug='running')),
  ('Носки компрессионные', 'RUN-005', '4600001000059', 280, (SELECT id FROM categories WHERE slug='running')),
  ('Гантели 5 кг (пара)', 'FIT-001', '4600002000017', 600, (SELECT id FROM categories WHERE slug='fitness')),
  ('Коврик для йоги Premium', 'FIT-002', '4600002000024', 350, (SELECT id FROM categories WHERE slug='fitness')),
  ('Фитнес-резинки набор', 'FIT-003', '4600002000031', 180, (SELECT id FROM categories WHERE slug='fitness')),
  ('Скакалка скоростная', 'FIT-004', '4600002000048', 120, (SELECT id FROM categories WHERE slug='fitness')),
  ('Перчатки тренировочные', 'FIT-005', '4600002000055', 250, (SELECT id FROM categories WHERE slug='fitness')),
  ('Очки для плавания Pro', 'SWM-001', '4600003000013', 320, (SELECT id FROM categories WHERE slug='swimming')),
  ('Шапочка силиконовая', 'SWM-002', '4600003000020', 90, (SELECT id FROM categories WHERE slug='swimming')),
  ('Плавки мужские Sport', 'SWM-003', '4600003000037', 450, (SELECT id FROM categories WHERE slug='swimming')),
  ('Доска для плавания', 'SWM-004', '4600003000044', 280, (SELECT id FROM categories WHERE slug='swimming')),
  ('Купальник спортивный', 'SWM-005', '4600003000051', 900, (SELECT id FROM categories WHERE slug='swimming')),
  ('Мяч футбольный Match', 'TEAM-001', '4600004000019', 700, (SELECT id FROM categories WHERE slug='team_sports')),
  ('Мяч баскетбольный Pro', 'TEAM-002', '4600004000026', 850, (SELECT id FROM categories WHERE slug='team_sports')),
  ('Мяч волейбольный Elite', 'TEAM-003', '4600004000033', 650, (SELECT id FROM categories WHERE slug='team_sports')),
  ('Щитки футбольные', 'TEAM-004', '4600004000040', 380, (SELECT id FROM categories WHERE slug='team_sports')),
  ('Форма баскетбольная', 'TEAM-005', '4600004000057', 1200, (SELECT id FROM categories WHERE slug='team_sports')),
  ('Палатка 2-местная Lite', 'OUT-001', '4600005000015', 3200, (SELECT id FROM categories WHERE slug='outdoor')),
  ('Спальник -5°C', 'OUT-002', '4600005000022', 2100, (SELECT id FROM categories WHERE slug='outdoor')),
  ('Рюкзак 40л Trek', 'OUT-003', '4600005000039', 1800, (SELECT id FROM categories WHERE slug='outdoor')),
  ('Термос 1л Steel', 'OUT-004', '4600005000046', 650, (SELECT id FROM categories WHERE slug='outdoor')),
  ('Фонарик налобный LED', 'OUT-005', '4600005000053', 280, (SELECT id FROM categories WHERE slug='outdoor')),
  ('Бутылка спортивная 750мл', 'ACC-001', '4600006000011', 120, (SELECT id FROM categories WHERE slug='accessories')),
  ('Сумка спортивная 30л', 'ACC-002', '4600006000028', 550, (SELECT id FROM categories WHERE slug='accessories')),
  ('Повязка на голову', 'ACC-003', '4600006000035', 90, (SELECT id FROM categories WHERE slug='accessories')),
  ('Часы спортивные Basic', 'ACC-004', '4600006000042', 1500, (SELECT id FROM categories WHERE slug='accessories')),
  ('Пояс для бега', 'ACC-005', '4600006000059', 200, (SELECT id FROM categories WHERE slug='accessories'));

-- Generate 90 days of sales data
DO $$
DECLARE
  d DATE;
  p_id INT;
  mp_id INT;
  qty INT;
  base_price NUMERIC;
  rev NUMERIC;
  comm NUMERIC;
  logi NUMERIC;
  profit NUMERIC;
  cost NUMERIC;
BEGIN
  FOR d IN SELECT generate_series(CURRENT_DATE - 90, CURRENT_DATE - 1, '1 day'::interval)::date
  LOOP
    FOR p_id IN SELECT id FROM products
    LOOP
      FOR mp_id IN SELECT id FROM marketplaces
      LOOP
        -- Not every product sells every day on every marketplace
        IF random() > 0.35 THEN
          CONTINUE;
        END IF;

        SELECT cost_price INTO cost FROM products WHERE id = p_id;
        base_price := cost * (1.8 + random() * 0.8);  -- markup 1.8x-2.6x
        qty := (1 + floor(random() * 8))::int;
        rev := ROUND((base_price * qty)::numeric, 2);
        comm := ROUND((rev * (0.05 + random() * 0.15))::numeric, 2);  -- 5-20% commission
        logi := ROUND((qty * (50 + random() * 150))::numeric, 2);     -- 50-200 per unit
        profit := ROUND((rev - (cost * qty) - comm - logi)::numeric, 2);

        INSERT INTO sales (product_id, marketplace_id, sale_date, quantity, revenue, net_profit, commission, logistics_cost)
        VALUES (p_id, mp_id, d, qty, rev, profit, comm, logi);

        -- Returns ~8% chance
        IF random() < 0.08 THEN
          INSERT INTO sales (product_id, marketplace_id, sale_date, quantity, revenue, net_profit, commission, logistics_cost)
          VALUES (p_id, mp_id, d, -1, -base_price, -(profit/qty), 0, 0);

          INSERT INTO returns (product_id, marketplace_id, quantity, return_date)
          VALUES (p_id, mp_id, 1, d);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;

-- Inventory
INSERT INTO inventory (product_id, marketplace_id, warehouse, quantity, recorded_at)
SELECT
  p.id,
  m.id,
  CASE (floor(random()*3))::int
    WHEN 0 THEN 'Москва'
    WHEN 1 THEN 'Санкт-Петербург'
    ELSE 'Казань'
  END,
  (10 + floor(random() * 200))::int,
  NOW()
FROM products p
CROSS JOIN marketplaces m
WHERE random() > 0.3;

-- Default user
INSERT INTO users (email, password_hash, name, role) VALUES
  ('admin@sportdata.ru', 'no_password_set', 'Администратор', 'admin')
ON CONFLICT (email) DO NOTHING;
