-- YourFit Analytics Platform
-- Миграция 001: Основная схема

-- ============================================
-- РОЛИ И ДОСТУПЫ
-- ============================================

CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    slug VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    level INT NOT NULL, -- 0=super_admin, 1=owner, 2=director, 3=head, 4=manager
    is_hidden BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO roles (slug, name, level, is_hidden) VALUES
    ('super_admin', 'Супер-администратор', 0, TRUE),
    ('owner', 'Собственник', 1, FALSE),
    ('director', 'Управляющий директор', 2, FALSE),
    ('head', 'Директор направления', 3, FALSE),
    ('manager', 'Менеджер', 4, FALSE)
ON CONFLICT (slug) DO NOTHING;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role_id INT REFERENCES roles(id) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_hidden BOOLEAN DEFAULT FALSE, -- super_admin скрыт от списков
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Направления продаж (для head-ролей)
CREATE TABLE IF NOT EXISTS departments (
    id SERIAL PRIMARY KEY,
    slug VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Привязка пользователя к направлениям
CREATE TABLE IF NOT EXISTS user_departments (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    department_id INT REFERENCES departments(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, department_id)
);

-- ============================================
-- МАРКЕТПЛЕЙСЫ
-- ============================================

CREATE TABLE IF NOT EXISTS marketplaces (
    id SERIAL PRIMARY KEY,
    slug VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    api_base_url VARCHAR(500),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO marketplaces (slug, name, api_base_url) VALUES
    ('wildberries', 'Wildberries', 'https://suppliers-api.wildberries.ru'),
    ('ozon', 'Ozon', 'https://api-seller.ozon.ru'),
    ('yandex_market', 'Яндекс Маркет', 'https://api.partner.market.yandex.ru'),
    ('avito', 'Авито', 'https://api.avito.ru')
ON CONFLICT (slug) DO NOTHING;

-- API ключи маркетплейсов (шифрованные)
CREATE TABLE IF NOT EXISTS marketplace_credentials (
    id SERIAL PRIMARY KEY,
    marketplace_id INT REFERENCES marketplaces(id) NOT NULL,
    name VARCHAR(200) NOT NULL, -- "WB основной кабинет"
    api_key_encrypted TEXT NOT NULL,
    client_id VARCHAR(200),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- ТОВАРЫ
-- ============================================

CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    parent_id INT REFERENCES categories(id),
    slug VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    department_id INT REFERENCES departments(id), -- привязка к направлению
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(100) UNIQUE NOT NULL, -- внутренний артикул YourFit
    name VARCHAR(500) NOT NULL,
    category_id INT REFERENCES categories(id),
    brand VARCHAR(100) DEFAULT 'YourFit',
    barcode VARCHAR(100),
    weight_g INT, -- вес в граммах
    cost_price DECIMAL(12,2), -- себестоимость
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Артикулы на маркетплейсах
CREATE TABLE IF NOT EXISTS product_mappings (
    id SERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id) ON DELETE CASCADE NOT NULL,
    marketplace_id INT REFERENCES marketplaces(id) NOT NULL,
    external_sku VARCHAR(200) NOT NULL, -- артикул на МП
    external_url VARCHAR(1000),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(marketplace_id, external_sku)
);

-- ============================================
-- ПРОДАЖИ И ФИНАНСЫ
-- ============================================

CREATE TABLE IF NOT EXISTS sales (
    id BIGSERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id) NOT NULL,
    marketplace_id INT REFERENCES marketplaces(id) NOT NULL,
    sale_date DATE NOT NULL,
    quantity INT NOT NULL DEFAULT 0,
    revenue DECIMAL(14,2) NOT NULL DEFAULT 0, -- выручка
    commission DECIMAL(14,2) DEFAULT 0, -- комиссия МП
    logistics_cost DECIMAL(14,2) DEFAULT 0, -- логистика
    net_profit DECIMAL(14,2) DEFAULT 0, -- чистая прибыль
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Партиционирование по дате для скорости
CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(sale_date);
CREATE INDEX IF NOT EXISTS idx_sales_product ON sales(product_id);
CREATE INDEX IF NOT EXISTS idx_sales_marketplace ON sales(marketplace_id);
CREATE INDEX IF NOT EXISTS idx_sales_product_date ON sales(product_id, sale_date);

-- ============================================
-- ОСТАТКИ (СТОКИ)
-- ============================================

CREATE TABLE IF NOT EXISTS inventory (
    id BIGSERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id) NOT NULL,
    marketplace_id INT REFERENCES marketplaces(id) NOT NULL,
    warehouse VARCHAR(200), -- название склада
    quantity INT NOT NULL DEFAULT 0,
    recorded_at TIMESTAMPTZ DEFAULT NOW(), -- когда зафиксировано
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_product ON inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_recorded ON inventory(recorded_at);

-- ============================================
-- ЗАКАЗЫ
-- ============================================

CREATE TABLE IF NOT EXISTS orders (
    id BIGSERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id) NOT NULL,
    marketplace_id INT REFERENCES marketplaces(id) NOT NULL,
    external_order_id VARCHAR(200),
    order_date TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) DEFAULT 'new', -- new, confirmed, shipped, delivered, returned, cancelled
    quantity INT NOT NULL DEFAULT 1,
    price DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_date ON orders(order_date);
CREATE INDEX IF NOT EXISTS idx_orders_product ON orders(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

-- ============================================
-- ВОЗВРАТЫ
-- ============================================

CREATE TABLE IF NOT EXISTS returns (
    id BIGSERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id) NOT NULL,
    marketplace_id INT REFERENCES marketplaces(id) NOT NULL,
    order_id BIGINT REFERENCES orders(id),
    return_date DATE NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    reason VARCHAR(500),
    penalty DECIMAL(12,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- СБОР ДАННЫХ (JOBS)
-- ============================================

CREATE TABLE IF NOT EXISTS sync_jobs (
    id BIGSERIAL PRIMARY KEY,
    marketplace_id INT REFERENCES marketplaces(id) NOT NULL,
    job_type VARCHAR(50) NOT NULL, -- 'sales', 'inventory', 'orders', 'returns', 'finance'
    status VARCHAR(20) DEFAULT 'pending', -- pending, running, completed, failed
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    records_processed INT DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- ИМПОРТ ИЗ GOOGLE ТАБЛИЦ
-- ============================================

CREATE TABLE IF NOT EXISTS import_logs (
    id BIGSERIAL PRIMARY KEY,
    source VARCHAR(50) NOT NULL, -- 'google_sheets', '1c', 'bitrix24', 'manual'
    file_name VARCHAR(500),
    status VARCHAR(20) DEFAULT 'pending',
    rows_total INT DEFAULT 0,
    rows_imported INT DEFAULT 0,
    rows_errors INT DEFAULT 0,
    error_details JSONB,
    imported_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- АУДИТ ЛОГ
-- ============================================

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id VARCHAR(100),
    details JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);

-- ============================================
-- ПРЕДСТАВЛЕНИЯ ДЛЯ ДАШБОРДОВ
-- ============================================

-- Продажи по дням с агрегацией
CREATE OR REPLACE VIEW v_daily_sales AS
SELECT 
    s.sale_date,
    p.sku,
    p.name AS product_name,
    c.name AS category_name,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    SUM(s.quantity) AS total_qty,
    SUM(s.revenue) AS total_revenue,
    SUM(s.commission) AS total_commission,
    SUM(s.logistics_cost) AS total_logistics,
    SUM(s.net_profit) AS total_profit
FROM sales s
JOIN products p ON p.id = s.product_id
JOIN marketplaces m ON m.id = s.marketplace_id
LEFT JOIN categories c ON c.id = p.category_id
GROUP BY s.sale_date, p.sku, p.name, c.name, m.slug, m.name;

-- Текущие остатки (последняя запись по каждому товару/МП)
CREATE OR REPLACE VIEW v_current_inventory AS
SELECT DISTINCT ON (i.product_id, i.marketplace_id)
    p.sku,
    p.name AS product_name,
    m.slug AS marketplace,
    i.warehouse,
    i.quantity,
    i.recorded_at
FROM inventory i
JOIN products p ON p.id = i.product_id
JOIN marketplaces m ON m.id = i.marketplace_id
ORDER BY i.product_id, i.marketplace_id, i.recorded_at DESC;

