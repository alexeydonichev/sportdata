-- migrations/012_rnp_pulse_extend.sql
-- Рука на пульсе: Расширение существующих таблиц

-- ============================================
-- 1. ENUM для статуса (вместо season)
-- ============================================

DO $$ BEGIN
    CREATE TYPE rnp_status AS ENUM (
        'liquidation',
        'action', 
        'monitoring',
        'completed',
        'paused'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================
-- 2. Расширяем rnp_items
-- ============================================

-- Статус
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS status rnp_status DEFAULT 'liquidation';

-- Цели
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS target_orders_day INT DEFAULT 0;
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS weekly_task_plan INT DEFAULT 0;

-- СПП
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS spp_percent DECIMAL(5,2) DEFAULT 0;

-- Дней хватит остатков
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS days_of_stock INT DEFAULT 0;
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS days_of_stock_7d INT DEFAULT 0;

-- 3 последних отзыва (звёзды 1-5)
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS review_1_stars INT CHECK (review_1_stars BETWEEN 1 AND 5);
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS review_2_stars INT CHECK (review_2_stars BETWEEN 1 AND 5);
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS review_3_stars INT CHECK (review_3_stars BETWEEN 1 AND 5);

-- reviews_ok: true если все 3 >= 4 звезды
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS reviews_ok BOOLEAN DEFAULT TRUE;

-- Флаги
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS has_discount BOOLEAN DEFAULT FALSE;
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS needs_attention BOOLEAN DEFAULT FALSE;

-- Менеджер (если нет)
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS manager_id UUID REFERENCES users(id);

-- Период
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS period_start DATE DEFAULT CURRENT_DATE;
ALTER TABLE rnp_items ADD COLUMN IF NOT EXISTS period_end DATE;

-- ============================================
-- 3. Расширяем rnp_daily_facts
-- ============================================

ALTER TABLE rnp_daily_facts ADD COLUMN IF NOT EXISTS spp_percent DECIMAL(5,2) DEFAULT 0;
ALTER TABLE rnp_daily_facts ADD COLUMN IF NOT EXISTS plan_orders_day INT DEFAULT 0;
ALTER TABLE rnp_daily_facts ADD COLUMN IF NOT EXISTS comment TEXT;

-- ============================================
-- 4. Таблица пунктов чек-листа
-- ============================================

CREATE TABLE IF NOT EXISTS rnp_checklist_items (
    id SERIAL PRIMARY KEY,
    item_id INT REFERENCES rnp_items(id) ON DELETE CASCADE,
    template_id INT REFERENCES rnp_checklist_templates(id),
    
    is_done BOOLEAN DEFAULT FALSE,
    done_at TIMESTAMPTZ,
    done_by UUID REFERENCES users(id),
    comment TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(item_id, template_id)
);

CREATE INDEX IF NOT EXISTS idx_rnp_checklist_item ON rnp_checklist_items(item_id);

-- ============================================
-- 5. История цен
-- ============================================

CREATE TABLE IF NOT EXISTS rnp_price_history (
    id SERIAL PRIMARY KEY,
    item_id INT REFERENCES rnp_items(id) ON DELETE CASCADE,
    
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    old_price DECIMAL(12,2),
    new_price DECIMAL(12,2),
    old_spp DECIMAL(5,2),
    new_spp DECIMAL(5,2),
    reason TEXT,
    changed_by UUID REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_rnp_price_history_item ON rnp_price_history(item_id);

-- ============================================
-- 6. Индексы
-- ============================================

CREATE INDEX IF NOT EXISTS idx_rnp_items_status ON rnp_items(status);
CREATE INDEX IF NOT EXISTS idx_rnp_items_reviews_ok ON rnp_items(reviews_ok);
CREATE INDEX IF NOT EXISTS idx_rnp_items_attention ON rnp_items(needs_attention);
CREATE INDEX IF NOT EXISTS idx_rnp_items_manager ON rnp_items(manager_id);

-- ============================================
-- 7. Функция: авто-расчёт reviews_ok
-- ============================================

CREATE OR REPLACE FUNCTION update_rnp_reviews_ok()
RETURNS TRIGGER AS $$
BEGIN
    NEW.reviews_ok := (
        COALESCE(NEW.review_1_stars, 5) >= 4 AND 
        COALESCE(NEW.review_2_stars, 5) >= 4 AND 
        COALESCE(NEW.review_3_stars, 5) >= 4
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rnp_reviews_ok ON rnp_items;
CREATE TRIGGER trg_rnp_reviews_ok
BEFORE INSERT OR UPDATE OF review_1_stars, review_2_stars, review_3_stars ON rnp_items
FOR EACH ROW EXECUTE FUNCTION update_rnp_reviews_ok();

-- ============================================
-- 8. Функция: авто-расчёт needs_attention
-- ============================================

CREATE OR REPLACE FUNCTION update_rnp_attention()
RETURNS TRIGGER AS $$
BEGIN
    NEW.needs_attention := (
        NEW.reviews_ok = FALSE OR
        COALESCE(NEW.days_of_stock_7d, 999) < 7 OR
        (NEW.plan_orders_qty > 0 AND 
         COALESCE(NEW.fact_orders_qty, 0)::DECIMAL / NEW.plan_orders_qty < 0.3 AND
         CURRENT_DATE - COALESCE(NEW.period_start, CURRENT_DATE) > 10)
    );
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rnp_attention ON rnp_items;
CREATE TRIGGER trg_rnp_attention
BEFORE INSERT OR UPDATE ON rnp_items
FOR EACH ROW EXECUTE FUNCTION update_rnp_attention();

-- ============================================
-- 9. VIEW: Сводка для UI
-- ============================================

CREATE OR REPLACE VIEW rnp_items_summary AS
SELECT 
    i.id,
    i.template_id,
    i.name,
    i.sku,
    i.nm_id,
    i.size,
    i.photo_url,
    i.category,
    i.status,
    
    -- Планы
    i.plan_orders_qty as target_orders_month,
    i.target_orders_day,
    i.plan_price,
    i.weekly_task_plan,
    
    -- Факт
    i.fact_orders_qty,
    i.fact_orders_rub,
    i.fact_avg_price as fact_price,
    i.spp_percent,
    
    -- Остатки
    i.stock_fbo,
    i.stock_fbs,
    i.stock_fbo + i.stock_fbs as stock_total,
    i.days_of_stock,
    i.days_of_stock_7d,
    
    -- Отзывы
    i.review_1_stars,
    i.review_2_stars,
    i.review_3_stars,
    i.reviews_ok,
    
    -- Ссылки
    i.content_task_url as tz_content_url,
    i.checklist_url,
    i.monitoring_url,
    
    -- Флаги
    i.has_discount,
    i.needs_attention,
    i.is_active,
    
    -- Комментарий
    i.notes as comment,
    
    -- Процент выполнения
    CASE 
        WHEN i.plan_orders_qty > 0 
        THEN ROUND((i.fact_orders_qty::DECIMAL / i.plan_orders_qty) * 100, 1)
        ELSE 0 
    END as completion_percent,
    
    -- Чек-лист статистика
    (SELECT COUNT(*) FILTER (WHERE is_done) FROM rnp_checklist_items ci WHERE ci.item_id = i.id) as checklist_done,
    (SELECT COUNT(*) FROM rnp_checklist_items ci WHERE ci.item_id = i.id) as checklist_total,
    
    -- Менеджер
    i.manager_id,
    u.first_name || ' ' || u.last_name as manager_name,
    
    -- Даты
    i.period_start,
    i.period_end,
    i.created_at,
    i.updated_at

FROM rnp_items i
LEFT JOIN users u ON u.id = i.manager_id
WHERE i.is_active = TRUE;

-- ============================================
-- 10. Обновляем существующие данные
-- ============================================

-- Установим статус liquidation для всех
UPDATE rnp_items SET status = 'liquidation' WHERE status IS NULL;

-- Рассчитаем target_orders_day из plan_orders_qty / 30
UPDATE rnp_items SET target_orders_day = CEIL(plan_orders_qty::DECIMAL / 30) WHERE target_orders_day = 0;

-- Установим period_start
UPDATE rnp_items SET period_start = DATE_TRUNC('month', CURRENT_DATE)::DATE WHERE period_start IS NULL;

