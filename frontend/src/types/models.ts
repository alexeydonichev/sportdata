// === Auth ===

export interface User {
  id: number;
  email: string;
  first_name: string;
  last_name: string;
  role: string;
  role_level: number;
  department?: string;
  is_active: boolean;
  created_at: string;
}

export type UserInfo = User;

export interface LoginResponse {
  token: string;
  user: User;
}

// === Dashboard ===
export interface DashboardChanges {
  revenue?: number;
  profit?: number;
  orders?: number;
  quantity?: number;
  avg_order?: number;
  margin?: number;
  commission?: number;
  logistics?: number;
  penalty?: number;
  returns?: number;
}

export interface MarketplaceBreakdownItem extends MarketplaceStats {}

export interface DashboardData {
  date_from: string;
  date_to: string;
  total_revenue: number;
  total_orders: number;
  total_profit: number;
  profit_margin_pct: number;
  total_quantity: number;
  total_sku: number;
  avg_order_value: number;
  total_commission: number;
  total_logistics: number;
  total_penalty?: number;
  total_returns?: number;
  total_returns_quantity?: number;
  changes?: DashboardChanges;
  by_marketplace: MarketplaceBreakdownItem[];
  top_products: TopProduct[];
}

export interface MetricCard {
  value: number;
  prev: number;
  delta: number;
}

export interface TopProduct {
  product_id: number;
  name: string;
  sku: string;
  revenue: number;
  profit: number;
  quantity: number;
  orders: number;
}

export interface LowStockItem {
  id: number;
  name: string;
  stock: number;
  days_left: number;
}

export interface ChartData {
  labels: string[];
  revenue: number[];
  orders: number[];
}

// === Products ===
export interface Product {
  id: number;
  nm_id?: number;
  sku: string;
  barcode?: string;
  name: string;
  category: string;
  brand?: string;
  size?: string;
  current_price?: number;
  cost_price?: number;
  avg_price: number;
  margin_pct: number;
  stock: number;
  quantity: number;
  revenue: number;
  profit: number;
  returns: number;
  return_pct: number;
  photo_url?: string;
}

export interface ProductsResponse {
  products: Product[];
  total: number;
  page: number;
  per_page: number;
}

export interface ProductDetailProduct {
  id: number;
  name: string;
  sku: string;
  barcode?: string;
  brand?: string;
  category?: string;
  category_slug?: string;
  created_at?: string;
  nm_id?: number;
  image_url?: string;
  cost_price: number;
  retail_price: number;
  discount_price: number;
  weight_g?: number;
  dimensions?: {
    length: number;
    width: number;
    height: number;
  };
}

export interface ProductDetailMetrics {
  total_revenue: number;
  total_profit: number;
  total_sold: number;
  total_orders: number;
  avg_price: number;
  total_commission: number;
  total_logistics: number;
  total_returns: number;
  margin_pct: number;
  return_pct: number;
}

export interface ProductDetailChanges {
  revenue: number | null;
  profit: number | null;
  quantity: number | null;
  orders: number | null;
}

export interface ProductDetailChartPoint {
  date: string;
  revenue: number;
  profit: number;
  quantity: number;
}

export interface ProductDetailFinance {
  revenue: number;
  for_pay: number;
  commission: number;
  logistics: number;
  penalty: number;
  acquiring: number;
  storage: number;
  deduction: number;
  acceptance: number;
  return_logistics: number;
  additional_payment: number;
  returns_amount: number;
  avg_spp_pct: number;
  avg_commission_pct: number;
  cogs: number;
  net_profit: number;
}

export interface ProductDetailAbc {
  grade: string;
  revenue_share: number;
}

export interface ProductDetailInventoryItem {
  warehouse: string;
  stock: number;
}

export interface ProductDetailInventory {
  total_stock: number;
  avg_daily_sales: number;
  days_of_stock: number;
  items: ProductDetailInventoryItem[];
}

export interface ProductDetailPriceHistoryPoint {
  week: string;
  price: number;
  discount_price?: number;
}

export interface ProductDetailMarketplace {
  marketplace: string;
  name: string;
  revenue: number;
  profit: number;
  quantity: number;
}

export interface ProductDetailGeoCountry {
  country: string;
  revenue: number;
  quantity: number;
}

export interface ProductDetailGeoWarehouse {
  warehouse: string;
  revenue: number;
  quantity: number;
}

export interface ProductDetailGeography {
  by_country: ProductDetailGeoCountry[];
  by_warehouse: ProductDetailGeoWarehouse[];
}

export interface ProductDetail {
  product: ProductDetailProduct;
  metrics: ProductDetailMetrics;
  changes: ProductDetailChanges;
  chart: ProductDetailChartPoint[];
  finance: ProductDetailFinance;
  abc?: ProductDetailAbc;
  inventory: ProductDetailInventory;
  price_history?: ProductDetailPriceHistoryPoint[];
  by_marketplace?: ProductDetailMarketplace[];
  geography?: ProductDetailGeography;
}

// === Categories ===
export interface Category {
  id: number;
  name: string;
  slug: string;
  products_count: number;
}

// === Marketplaces ===
export interface Marketplace {
  id: number;
  name: string;
  code: string;
  is_active: boolean;
}

// === Sales ===
export interface Sale {
  id: number;
  date: string;
  product_id: number;
  product_name: string;
  sku: string;
  category: string;
  quantity: number;
  price: number;
  total: number;
  revenue: number;
  profit: number;
  commission: number;
  logistics: number;
  marketplace: string;
}

export interface SalesResponse {
  sales: Sale[];
  items: Sale[];
  total: number;
  page: number;
  pages: number;
  per_page: number;
  summary: {
    total_revenue: number;
    total_orders: number;
    avg_check: number;
  };
}

// === Inventory ===
export interface InventoryItem {
  id: number;
  product_id: number;
  product_name: string;
  name: string;
  sku: string;
  category: string;
  warehouse: string;
  stock: number;
  stock_fbo: number;
  stock_fbs: number;
  reserved: number;
  in_transit: number;
  avg_daily_sales: number;
  days_of_stock: number;
}

export interface InventorySummary {
  products_in_stock: number;
  warehouses: number;
  total_stock: number;
}

export interface InventorySummary {
  products_in_stock: number;
  warehouses: number;
  total_stock: number;
}

export interface InventoryResponse {
  items: InventoryItem[];
  total: number;
  page: number;
  per_page: number;
  summary: InventorySummary;
}

// === Analytics ===
export interface PnLData {
  period: string;
  revenue: number;
  cost: number;
  gross_profit: number;
  expenses: number;
  net_profit: number;
  margin_pct: number;
  rows: PnLRow[];
}

export interface PnLRow {
  category: string;
  revenue: number;
  cost: number;
  gross_profit: number;
  margin_pct: number;
}

export interface ABCData {
  products: ABCProduct[];
  summary: {
    a_count: number;
    b_count: number;
    c_count: number;
    a_revenue_pct: number;
    b_revenue_pct: number;
    c_revenue_pct: number;
  };
}

export interface ABCProduct {
  id: number;
  name: string;
  sku: string;
  category: string;
  abc_class: "A" | "B" | "C";
  revenue: number;
  revenue_pct: number;
  cumulative_pct: number;
}

export interface UnitEconomicsData {
  products: UnitEconomicsProduct[];
  summary: {
    avg_margin: number;
    avg_roi: number;
    profitable_count: number;
    unprofitable_count: number;
  };
}

export interface UnitEconomicsProduct {
  id: number;
  name: string;
  sku: string;
  price: number;
  cost: number;
  logistics: number;
  commission: number;
  margin: number;
  margin_pct: number;
  roi: number;
}

export interface TrendingData {
  growing: TrendingProduct[];
  declining: TrendingProduct[];
}

export interface TrendingProduct {
  id: number;
  name: string;
  sku: string;
  current_sales: number;
  prev_sales: number;
  growth_pct: number;
}

// === Notifications ===
export interface Notification {
  id: number;
  type: string;
  title: string;
  message: string;
  is_read: boolean;
  created_at: string;
}

export interface NotificationsSummary {
  total: number;
  critical: number;
  warning: number;
}

export interface NotificationsResponse {
  notifications: Notification[];
  alerts: NotificationAlert[];
  unread_count: number;
  summary: NotificationsSummary;
}

// === Sync ===
export interface SyncStatus {
  marketplace: string;
  last_sync: string | null;
  status: "idle" | "running" | "error";
  error?: string;
}

export interface SyncCredential {
  id: number;
  marketplace: string;
  marketplace_id?: number;
  slug: string;
  name: string;
  credential_name?: string;
  is_configured: boolean;
  status: "connected" | "disconnected" | "error" | string;
  last_verified: string | null;
  last_sync?: SyncHistoryItem | null;
}

export interface SyncHistoryItem {
  id: number;
  marketplace: string;
  marketplace_name: string;
  job_type: string;
  created_at: string;
  started_at: string;
  finished_at: string | null;
  completed_at: string | null;
  status: string;
  records_synced: number;
  records_processed: number;
  duration_sec: number;
  message?: string;
  error?: string;
  error_message?: string;
}

// === Users Management ===
export interface ManagedUser {
  id: number;
  email: string;
  first_name: string;
  last_name: string;
  role_id: number;
  role_name: string;
  department_id?: number;
  department_name?: string;
  is_active: boolean;
  created_at: string;
}

export interface Role {
  id: number;
  name: string;
  slug: string;
  level: number;
}

export interface Department {
  id: number;
  name: string;
  slug: string;
}

// === РНП (Рука На Пульсе) ===
export interface Manager {
  id: number;
  name: string;
}

export interface ChecklistTemplate {
  id: number;
  name: string;
  sort_order: number;
}

export interface RNPTemplate {
  id: number;
  year: number;
  month: number;
  status: "draft" | "active" | "closed";
  marketplace: string;
  marketplace_id: number;
  project_id: number;
  project_name: string;
  manager_id: string;
  manager_name: string;
  total_plan_qty: number;
  total_plan_rub: number;
  total_fact_qty: number;
  total_fact_rub: number;
  completion_pct: number;
  items_count: number;
  days_in_month: number;
  days_passed: number;
  days_left: number;
  created_at: string;
}

export interface RNPTemplateDetail {
  id: number;
  year: number;
  month: number;
  days_passed: number;
  days_left: number;
  days_in_month: number;
}

export interface RNPItem {
  id: number;
  nm_id: number;
  sku: string;
  size: string;
  name: string;
  category: string;
  season: string;
  photo_url: string;
  
  // Менеджер
  manager_id: number | null;
  manager_name: string;
  
  // План
  plan_orders_qty: number;
  plan_orders_rub: number;
  plan_price: number;
  plan_daily_avg: number;
  
  // Факт
  fact_orders_qty: number;
  fact_orders_rub: number;
  fact_avg_price: number;
  fact_daily_avg: number;
  
  // Выполнение
  completion_pct_qty: number;
  completion_status: "under" | "ok" | "over";
  
  // Остатки
  stock_fbo: number;
  stock_fbs: number;
  stock_in_transit: number;
  stock_1c: number;
  
  // Оборачиваемость
  turnover_mtd: number;
  turnover_7d: number;
  
  // Отзывы
  reviews_avg_rating: number;
  reviews_status: string;
  
  // Чеклист
  checklist_done: number;
  checklist_total: number;
  
  // Статус работы
  item_status: "ok" | "risk" | "action";
}

export interface RNPItemsResponse {
  template: RNPTemplateDetail;
  items: RNPItem[];
  count: number;
}

export interface RNPDailyStat {
  id: number;
  date: string;
  orders_qty: number;
  orders_rub: number;
  plan_qty: number;
  plan_rub: number;
  delta_qty: number;
  delta_pct: number;
}

export interface RNPChecklistItem {
  id: number;
  template_id: number;
  name: string;
  is_done: boolean;
  done_at: string | null;
  done_by: string;
  comment: string;
}

// === Projects ===
export interface Project {
  id: number;
  name: string;
  slug: string;
}

// === Audit ===
export interface AuditLogEntry {
  id: number;
  user_id: number;
  user_email: string;
  action: string;
  entity: string;
  entity_id: number;
  details: Record<string, unknown>;
  ip_address: string;
  created_at: string;
}

// === System ===
export interface SystemInfo {
  version: string;
  go_version: string;
  uptime: string;
  db_connections: number;
  redis_connected: boolean;
  memory_mb: number;
}

// === Period constants ===
export const PERIOD_DAYS: Record<string, number> = {
  "7d": 7,
  "30d": 30,
  "90d": 90,
  "365d": 365,
};

export type PeriodKey = keyof typeof PERIOD_DAYS;

// === Notification Alerts ===
export interface NotificationAlert {
  id: string | number;
  type: string;
  severity: "critical" | "warning" | "info" | "error";
  title?: string;
  message: string;
  product_id?: number;
  product_name?: string;
  sku?: string;
  value?: number;
  threshold?: number;
  created_at: string;
}

// === Chart Types ===
export interface ChartDataPoint {
  date: string;
  revenue: number;
  profit: number;
}

// === Chart Types ===
export interface ChartDataPoint {
  date: string;
  revenue: number;
  profit: number;
}

// Missing types for imports
export interface RNPTemplatesResponse {
  templates: RNPTemplate[];
  total: number;
}

export interface DashboardKPI {
  total_revenue: number;
  total_profit: number;
  total_orders: number;
  total_quantity: number;
  total_sku: number;
  avg_order_value: number;
  profit_margin_pct: number;
  total_commission: number;
  total_logistics: number;
  total_penalty: number;
  total_returns: number;
  total_returns_quantity: number;
  date_from: string;
  date_to: string;
}

export interface MarketplaceStats {
  marketplace: string;
  name?: string;
  revenue: number;
  orders: number;
  profit?: number;
  share?: number;
  share_pct?: number;
}

export interface Alert {
  id: string | number;
  type: string;
  message: string;
  severity: 'info' | 'warning' | 'error' | 'critical';
  title?: string;
  product_id?: number;
  product_name?: string;
  sku?: string;
  value?: number;
  threshold?: number;
  created_at: string;
}

export interface NotificationsData {
  alerts: NotificationAlert[];
  summary: {
    total: number;
    critical: number;
    warning: number;
    info: number;
  };
}

export interface InventoryData {
  items: InventoryItem[];
  summary: InventorySummary;
}

export interface InventoryRow extends InventoryItem {}

export interface SaleRow extends Sale {}

export interface SalesPage {
  items: SaleRow[];
  total: number;
  page: number;
  limit: number;
  pages: number;
}

export interface ProductListItem extends Product {}

// === Returns Analytics ===
export interface ReturnsAnalyticsSummary {
  total_returns: number;
  return_rate: number;
  return_amount: number;
  lost_profit: number;
  return_logistics: number;
}

export interface ReturnsAnalyticsChanges {
  returns: number;
  return_rate: number;
  return_amount: number;
}

export interface ReturnsAnalyticsDaily {
  date: string;
  return_qty: number;
  return_amount: number;
}

export interface ReturnsAnalyticsByProduct {
  product_id: number;
  sku: string;
  name: string;
  category: string;
  sales_qty: number;
  return_qty: number;
  return_rate: number;
  return_amount: number;
}

export interface ReturnsAnalyticsByCategory {
  category: string;
  return_qty: number;
  return_rate: number;
}

export interface ReturnsAnalyticsByWarehouse {
  warehouse: string;
  return_qty: number;
  return_rate: number;
}

export interface ReturnsAnalytics {
  summary: ReturnsAnalyticsSummary;
  changes: ReturnsAnalyticsChanges;
  daily: ReturnsAnalyticsDaily[];
  by_product: ReturnsAnalyticsByProduct[];
  by_category: ReturnsAnalyticsByCategory[];
  by_warehouse: ReturnsAnalyticsByWarehouse[];
}

export type SyncStatusResponse = SyncStatus[];
