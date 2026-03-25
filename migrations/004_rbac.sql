-- ============================================
-- Migration 004: RBAC — Role-Based Access Control
-- ============================================

-- 1. Add role fields to users
ALTER TABLE users ADD COLUMN IF NOT EXISTS role_level INT NOT NULL DEFAULT 5;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS invited_by INT REFERENCES users(id);
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

-- Update existing admin user
UPDATE users SET role_level = 0 WHERE email = 'admin@sportdata.ru';
UPDATE users SET role = 'owner' WHERE email = 'admin@sportdata.ru';

-- 2. Role definitions (reference table, not for joins — just documentation)
CREATE TABLE IF NOT EXISTS role_definitions (
  level INT PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  description TEXT
);

INSERT INTO role_definitions (level, slug, name, description) VALUES
  (0, 'owner',        'Владелец',              'Полный доступ. Суперадмин платформы.'),
  (1, 'co_owner',     'Совладелец',            'Полный доступ кроме управления владельцем.'),
  (2, 'director',     'Директор / Гл. аналитик', 'Все данные, настройки, отчёты. Без управления ролями 0-1.'),
  (3, 'manager',      'Руководитель',          'Данные своих магазинов/направлений. Управление уровнями 4-5.'),
  (4, 'shop_manager', 'Менеджер магазина',     'Только свой магазин/направление. Чтение.'),
  (5, 'support',      'Поддержка',             'Просмотр заказов и товаров. Без аналитики.')
ON CONFLICT (level) DO UPDATE SET
  slug = EXCLUDED.slug,
  name = EXCLUDED.name,
  description = EXCLUDED.description;

-- 3. Scopes — привязка пользователей к конкретным магазинам/категориям
CREATE TABLE IF NOT EXISTS user_scopes (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  scope_type TEXT NOT NULL CHECK (scope_type IN ('marketplace', 'category', 'all')),
  scope_value TEXT,  -- marketplace slug, category slug, or NULL for 'all'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_scopes_unique
  ON user_scopes(user_id, scope_type, COALESCE(scope_value, '__all__'));

CREATE INDEX IF NOT EXISTS idx_user_scopes_user ON user_scopes(user_id);

-- 4. Invite tokens — для приглашения новых пользователей
CREATE TABLE IF NOT EXISTS invite_tokens (
  id SERIAL PRIMARY KEY,
  token TEXT UNIQUE NOT NULL,
  email TEXT NOT NULL,
  role_level INT NOT NULL,
  scopes JSONB DEFAULT '[]',
  created_by INT NOT NULL REFERENCES users(id),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invite_tokens_token ON invite_tokens(token);

-- 5. Sessions tracking (optional but useful)
CREATE TABLE IF NOT EXISTS user_sessions (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_hash ON user_sessions(token_hash);

-- 6. Add indexes for users table
CREATE INDEX IF NOT EXISTS idx_users_role_level ON users(role_level);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active) WHERE is_active = true;

