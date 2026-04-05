-- Миграция 006: РНП (Расходы на продажу) - учёт расходов по маркетплейсам

-- ============================================
-- ТАБЛИЦА РНП
-- ============================================

CREATE TABLE IF NOT EXISTS rnp (
    id BIGSERIAL PRIMARY KEY,
    marketplace_id INT REFERENCES marketplaces(id) NOT NULL,
    operation_date DATE NOT NULL,
    category VARCHAR(100) NOT NULL, -- 'logistics', 'storage', 'commission', 'advertising', 'penalty', 'returns', 'other'
    subcategory VARCHAR(200), -- детализация
    description TEXT,
    amount DECIMAL(14,2) NOT NULL, -- сумма (отрицательная = расход)
    document_id VARCHAR(200), -- внешний ID документа
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rnp_date ON rnp(operation_date);
CREATE INDEX IF NOT EXISTS idx_rnp_marketplace ON rnp(marketplace_id);
CREATE INDEX IF NOT EXISTS idx_rnp_category ON rnp(category);
CREATE INDEX IF NOT EXISTS idx_rnp_date_mp ON rnp(operation_date, marketplace_id);

-- ============================================
-- СПРАВОЧНИК КАТЕГОРИЙ РНП
-- ============================================

CREATE TABLE IF NOT EXISTS rnp_categories (
    id SERIAL PRIMARY KEY,
    slug VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    color VARCHAR(7) DEFAULT '#6B7280', -- HEX цвет для UI
    sort_order INT DEFAULT 0
);

INSERT INTO rnp_categories (slug, name, color, sort_order) VALUES
    ('logistics', 'Логистика', '#3B82F6', 1),
    ('storage', 'Хранение', '#8B5CF6', 2),
    ('commission', 'Комиссия МП', '#F59E0B', 3),
    ('advertising', 'Реклама', '#10B981', 4),
    ('penalty', 'Штрафы', '#EF4444', 5),
    ('returns', 'Обработка возвратов', '#F97316', 6),
    ('packaging', 'Упаковка', '#06B6D4', 7),
    ('other', 'Прочее', '#6B7280', 99)
ON CONFLICT (slug) DO NOTHING;

-- ============================================
-- VIEW ДЛЯ АГРЕГАЦИИ
-- ============================================

CREATE OR REPLACE VIEW v_rnp_summary AS
SELECT 
    r.operation_date,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    r.category,
    rc.name AS category_name,
    rc.color AS category_color,
    SUM(r.amount) AS total_amount,
    COUNT(*) AS operations_count
FROM rnp r
JOIN marketplaces m ON m.id = r.marketplace_id
LEFT JOIN rnp_categories rc ON rc.slug = r.category
GROUP BY r.operation_date, m.slug, m.name, r.category, rc.name, rc.color;

-- View для месячной статистики
CREATE OR REPLACE VIEW v_rnp_monthly AS
SELECT 
    DATE_TRUNC('month', r.operation_date)::DATE AS month,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    r.category,
    rc.name AS category_name,
    SUM(r.amount) AS total_amount,
    COUNT(*) AS operations_count
FROM rnp r
JOIN marketplaces m ON m.id = r.marketplace_id
LEFT JOIN rnp_categories rc ON rc.slug = r.category
GROUP BY DATE_TRUNC('month', r.operation_date), m.slug, m.name, r.category, rc.name;
