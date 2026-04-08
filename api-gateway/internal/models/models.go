package models

import "time"

// ============================================
// РОЛИ И ПОЛЬЗОВАТЕЛИ
// ============================================

type Role struct {
	ID       int    `json:"id"`
	Slug     string `json:"slug"`
	Name     string `json:"name"`
	Level    int    `json:"level"`
	IsHidden bool   `json:"-"` // не отдаём в JSON
}

type User struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	FirstName   string     `json:"first_name"`
	LastName    string     `json:"last_name"`
	RoleID      int        `json:"-"`
	Role        *Role      `json:"role,omitempty"`
	IsActive    bool       `json:"is_active"`
	IsHidden    bool       `json:"-"`
	LastLoginAt *time.Time `json:"last_login_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
}

type Department struct {
	ID   int    `json:"id"`
	Slug string `json:"slug"`
	Name string `json:"name"`
}

// ============================================
// МАРКЕТПЛЕЙСЫ
// ============================================

type Marketplace struct {
	ID       int    `json:"id"`
	Slug     string `json:"slug"`
	Name     string `json:"name"`
	IsActive bool   `json:"is_active"`
}

// ============================================
// ТОВАРЫ
// ============================================

type Category struct {
	ID       int         `json:"id"`
	ParentID *int        `json:"parent_id,omitempty"`
	Slug     string      `json:"slug"`
	Name     string      `json:"name"`
	Children []*Category `json:"children,omitempty"`
}

type Product struct {
	ID        int       `json:"id"`
	SKU       string    `json:"sku"`
	Name      string    `json:"name"`
	Category  *Category `json:"category,omitempty"`
	Brand     string    `json:"brand"`
	Barcode   string    `json:"barcode,omitempty"`
	WeightG   *int      `json:"weight_g,omitempty"`
	CostPrice *float64  `json:"cost_price,omitempty"`
	IsActive  bool      `json:"is_active"`
}

type ProductMapping struct {
	ID            int    `json:"id"`
	ProductID     int    `json:"product_id"`
	MarketplaceID int    `json:"marketplace_id"`
	Marketplace   string `json:"marketplace"`
	ExternalSKU   string `json:"external_sku"`
	ExternalURL   string `json:"external_url,omitempty"`
}

// ============================================
// ПРОДАЖИ И АНАЛИТИКА
// ============================================

type Sale struct {
	ID            int64   `json:"id"`
	ProductID     int     `json:"product_id"`
	MarketplaceID int     `json:"marketplace_id"`
	SaleDate      string  `json:"sale_date"`
	Quantity      int     `json:"quantity"`
	Revenue       float64 `json:"revenue"`
	Commission    float64 `json:"commission"`
	LogisticsCost float64 `json:"logistics_cost"`
	NetProfit     float64 `json:"net_profit"`
}

type DailySales struct {
	Date            string  `json:"date"`
	SKU             string  `json:"sku"`
	ProductName     string  `json:"product_name"`
	CategoryName    string  `json:"category_name"`
	Marketplace     string  `json:"marketplace"`
	MarketplaceName string  `json:"marketplace_name"`
	TotalQty        int     `json:"total_qty"`
	TotalRevenue    float64 `json:"total_revenue"`
	TotalCommission float64 `json:"total_commission"`
	TotalLogistics  float64 `json:"total_logistics"`
	TotalProfit     float64 `json:"total_profit"`
}

// ============================================
// ОСТАТКИ
// ============================================

type InventoryItem struct {
	SKU         string    `json:"sku"`
	ProductName string    `json:"product_name"`
	Marketplace string    `json:"marketplace"`
	Warehouse   string    `json:"warehouse"`
	Quantity    int       `json:"quantity"`
	RecordedAt  time.Time `json:"recorded_at"`
}

// ============================================
// ЗАКАЗЫ
// ============================================

type Order struct {
	ID              int64     `json:"id"`
	ProductID       int       `json:"product_id"`
	MarketplaceID   int       `json:"marketplace_id"`
	ExternalOrderID string    `json:"external_order_id"`
	OrderDate       time.Time `json:"order_date"`
	Status          string    `json:"status"`
	Quantity        int       `json:"quantity"`
	Price           float64   `json:"price"`
}

// ============================================
// СИНХРОНИЗАЦИЯ
// ============================================

type SyncJob struct {
	ID               int64      `json:"id"`
	MarketplaceID    int        `json:"marketplace_id"`
	Marketplace      string     `json:"marketplace"`
	JobType          string     `json:"job_type"`
	Status           string     `json:"status"`
	StartedAt        *time.Time `json:"started_at,omitempty"`
	CompletedAt      *time.Time `json:"completed_at,omitempty"`
	RecordsProcessed int        `json:"records_processed"`
	ErrorMessage     string     `json:"error_message,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
}

// ============================================
// ДАШБОРД
// ============================================

type PeriodFilter struct {
	Period        string // 1d, 3d, 7d, 30d, 90d, 180d, 365d, all
	DateFrom      string
	DateTo        string
	MarketplaceID *int
	CategoryID    *int
	ProductID     *int
}

type DashboardOverview struct {
	Period         string               `json:"period"`
	TotalRevenue   float64              `json:"total_revenue"`
	TotalProfit    float64              `json:"total_profit"`
	TotalOrders    int                  `json:"total_orders"`
	TotalQuantity  int                  `json:"total_quantity"`
	TotalReturns   int                  `json:"total_returns"`
	AvgOrderValue  float64              `json:"avg_order_value"`
	ProfitMargin   float64              `json:"profit_margin_pct"`
	RevenueChange  float64              `json:"revenue_change_pct"`
	ProfitChange   float64              `json:"profit_change_pct"`
	OrdersChange   float64              `json:"orders_change_pct"`
	ActiveProducts int                  `json:"active_products"`
	TotalSKU       int                  `json:"total_sku"`
	ByMarketplace  []MarketplaceSummary `json:"by_marketplace"`
	TopProducts    []ProductSummary     `json:"top_products"`
}

type MarketplaceSummary struct {
	Marketplace string  `json:"marketplace"`
	Name        string  `json:"name"`
	Revenue     float64 `json:"revenue"`
	Profit      float64 `json:"profit"`
	Orders      int     `json:"orders"`
	Quantity    int     `json:"quantity"`
	Share       float64 `json:"share_pct"`
}

type ProductSummary struct {
	SKU      string  `json:"sku"`
	Name     string  `json:"name"`
	Revenue  float64 `json:"revenue"`
	Profit   float64 `json:"profit"`
	Quantity int     `json:"quantity"`
}
