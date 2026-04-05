CREATE TABLE IF NOT EXISTS projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(50) NOT NULL UNIQUE,
    director_id UUID REFERENCES users(id),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS project_members (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id),
    user_id UUID NOT NULL REFERENCES users(id),
    marketplace_id INT REFERENCES marketplaces(id),
    role VARCHAR(20) DEFAULT 'manager',
    UNIQUE(project_id, user_id, marketplace_id)
);

CREATE TABLE IF NOT EXISTS rnp_templates (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id),
    manager_id UUID NOT NULL REFERENCES users(id),
    marketplace_id INT NOT NULL REFERENCES marketplaces(id),
    year INT NOT NULL,
    month INT NOT NULL CHECK (month BETWEEN 1 AND 12),
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(manager_id, marketplace_id, year, month)
);

CREATE TABLE IF NOT EXISTS rnp_items (
    id SERIAL PRIMARY KEY,
    template_id INT NOT NULL REFERENCES rnp_templates(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id),
    nm_id BIGINT,
    sku VARCHAR(100),
    barcode VARCHAR(50),
    size VARCHAR(20) DEFAULT '0',
    name VARCHAR(500),
    category VARCHAR(200),
    season VARCHAR(20) DEFAULT 'all_season',
    photo_url TEXT,
    plan_orders_qty INT DEFAULT 0,
    plan_orders_rub DECIMAL(12,2) DEFAULT 0,
    plan_price DECIMAL(10,2) DEFAULT 0,
    fact_orders_qty INT DEFAULT 0,
    fact_orders_rub DECIMAL(12,2) DEFAULT 0,
    fact_avg_price DECIMAL(10,2) DEFAULT 0,
    stock_fbo INT DEFAULT 0,
    stock_fbs INT DEFAULT 0,
    stock_in_transit INT DEFAULT 0,
    stock_1c INT DEFAULT 0,
    turnover_mtd DECIMAL(6,1),
    turnover_7d DECIMAL(6,1),
    reviews_avg_rating DECIMAL(2,1),
    reviews_status VARCHAR(10),
    is_active BOOLEAN DEFAULT true,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rnp_daily (
    id SERIAL PRIMARY KEY,
    item_id INT NOT NULL REFERENCES rnp_items(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    target_qty INT DEFAULT 0,
    fact_qty INT DEFAULT 0,
    fact_rub DECIMAL(10,2) DEFAULT 0,
    fact_price DECIMAL(10,2),
    status VARCHAR(10),
    UNIQUE(item_id, date)
);

CREATE INDEX IF NOT EXISTS idx_rnp_templates_manager ON rnp_templates(manager_id);
CREATE INDEX IF NOT EXISTS idx_rnp_items_template ON rnp_items(template_id);
CREATE INDEX IF NOT EXISTS idx_rnp_items_nm ON rnp_items(nm_id);
CREATE INDEX IF NOT EXISTS idx_rnp_daily_date ON rnp_daily(date);

INSERT INTO projects (name, slug) VALUES
('Спорт', 'sport'),
('Игрушки/Носки/Обувь', 'toys-socks-shoes'),
('Сладкий дом', 'sweet-home'),
('Модный дом', 'fashion-home')
ON CONFLICT (slug) DO NOTHING;
