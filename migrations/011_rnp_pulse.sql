-- Статусы товара в РНП
DO $$ BEGIN
    CREATE TYPE rnp_status AS ENUM ('liquidation', 'action', 'monitoring', 'completed');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Добавляем новые колонки в rnp_items
ALTER TABLE rnp_items 
    ADD COLUMN IF NOT EXISTS status rnp_status DEFAULT 'liquidation',
    ADD COLUMN IF NOT EXISTS target_orders_day INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS weekly_task_plan INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS spp_percent DECIMAL(5,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS days_of_stock INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS days_of_stock_7d INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS review_1_stars INT,
    ADD COLUMN IF NOT EXISTS review_2_stars INT,
    ADD COLUMN IF NOT EXISTS review_3_stars INT,
    ADD COLUMN IF NOT EXISTS reviews_ok BOOLEAN DEFAULT true,
    ADD COLUMN IF NOT EXISTS content_task_url TEXT,
    ADD COLUMN IF NOT EXISTS checklist_url TEXT,
    ADD COLUMN IF NOT EXISTS monitoring_url TEXT,
    ADD COLUMN IF NOT EXISTS has_discount BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS needs_attention BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS notes TEXT;

-- Дневная статистика
CREATE TABLE IF NOT EXISTS rnp_daily_facts (
    id SERIAL PRIMARY KEY,
    item_id INT NOT NULL REFERENCES rnp_items(id) ON DELETE CASCADE,
    fact_date DATE NOT NULL,
    target_orders_qty INT DEFAULT 0,
    fact_orders_qty INT DEFAULT 0,
    fact_orders_rub DECIMAL(12,2),
    stock_fbo INT DEFAULT 0,
    stock_fbs INT DEFAULT 0,
    current_price DECIMAL(10,2),
    discount_percent DECIMAL(5,2) DEFAULT 0,
    spp_percent DECIMAL(5,2) DEFAULT 0,
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(item_id, fact_date)
);

-- Шаблоны чек-листа
CREATE TABLE IF NOT EXISTS rnp_checklist_templates (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    sort_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Чек-лист товара
CREATE TABLE IF NOT EXISTS rnp_checklist_items (
    id SERIAL PRIMARY KEY,
    item_id INT NOT NULL REFERENCES rnp_items(id) ON DELETE CASCADE,
    template_id INT NOT NULL REFERENCES rnp_checklist_templates(id),
    is_done BOOLEAN DEFAULT false,
    done_at TIMESTAMPTZ,
    done_by UUID REFERENCES users(id),
    comment TEXT,
    UNIQUE(item_id, template_id)
);

-- Индексы
CREATE INDEX IF NOT EXISTS idx_rnp_daily_facts_item_date ON rnp_daily_facts(item_id, fact_date);
CREATE INDEX IF NOT EXISTS idx_rnp_items_status ON rnp_items(status);
CREATE INDEX IF NOT EXISTS idx_rnp_items_attention ON rnp_items(needs_attention) WHERE needs_attention = true;
CREATE INDEX IF NOT EXISTS idx_rnp_checklist_item ON rnp_checklist_items(item_id);

-- Базовые пункты чек-листа
INSERT INTO rnp_checklist_templates (name, sort_order) VALUES
    ('Проверить фото товара', 10),
    ('Обновить описание', 20),
    ('Проверить SEO-теги', 30),
    ('Настроить рекламу', 40),
    ('Ответить на отзывы', 50),
    ('Проверить остатки', 60),
    ('Актуализировать цену', 70)
ON CONFLICT DO NOTHING;
