// ============================================================
// Domain Models — единые типы для всего приложения
// ============================================================

// --- Dashboard ---

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
  date_from: string | null;
  date_to: string | null;
}

export interface DashboardChanges {
  revenue: number | null;
  profit: number | null;
  orders: number | null;
  quantity: number | null;
  avg_order: number | null;
  margin: number | null;
  commission: number | null;
  logistics: number | null;
}

export interface DashboardData {
  period: string;
  date_from: string | null;
  date_to: string | null;
  total_revenue: number;
  total_profit: number;
  total_orders: number;
  total_quantity: number;
  total_sku: number;
  avg_order_value: number;
  profit_margin_pct: number;
  total_commission: number;
  total_logistics: number;
  changes: DashboardChanges;
  by_marketplace: MarketplaceStats[];
  top_products: TopProduct[] | null;
}

export interface ChartDataPoint {
  date: string;
  revenue: number;
  profit: number;
  orders: number;
  quantity: number;
}

// --- Products ---

export interface ProductListItem {
  id: string;
  name: string;
  sku: string;
  cost_price: number;
  category: string;
  category_slug: string;
  avg_price: number;
  revenue: number;
  profit: number;
  quantity: number;
  orders: number;
  margin_pct: number;
  stock: number;
  returns: number;
  return_pct: number;
}

export interface ProductDetail {
  product: {
    id: string;
    name: string;
    sku: string;
    barcode: string;
    cost_price: number;
    price: number;
    category: string;
    category_slug: string;
    created_at: string;
  };
  metrics: {
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
  };
  changes: {
    revenue: number | null;
    profit: number | null;
    quantity: number | null;
    orders: number | null;
  };
  chart: ChartDataPoint[];
  inventory: {
    items: { warehouse: string; stock: number; updated_at: string }[];
    total_stock: number;
    avg_daily_sales: number;
    days_of_stock: number;
  };
  abc: { grade: "A" | "B" | "C"; revenue_share: number };
  by_marketplace: MarketplaceStats[];
}

// --- Sales ---

export interface SaleRow {
  id: string;
  date: string;
  product_name: string;
  sku: string;
  category: string;
  quantity: number;
  revenue: number;
  profit: number;
  commission: number;
  logistics: number;
  marketplace: string;
}

export interface SalesPage {
  items: SaleRow[];
  total: number;
  page: number;
  limit: number;
  pages: number;
}

// --- Inventory ---

export interface InventoryRow {
  product_id: string;
  name: string;
  sku: string;
  category: string;
  warehouse: string;
  stock: number;
  avg_daily_sales: number;
  days_of_stock: number;
}

export interface InventorySummary {
  total_stock: number;
  products_in_stock: number;
  warehouses: number;
}

export interface InventoryData {
  items: InventoryRow[];
  summary: InventorySummary;
}

// --- Categories ---

export interface Category {
  slug: string;
  name: string;
  product_count: number;
  revenue: number;
}

// --- Analytics ---

export interface ABCProduct {
  id: string;
  name: string;
  sku: string;
  category: string;
  revenue: number;
  profit: number;
  quantity: number;
  orders: number;
}

export interface MarketplaceStats {
  marketplace: string;
  name: string;
  revenue: number;
  profit: number;
  quantity: number;
  share_pct: number;
}

export interface TopProduct {
  product_id: string;
  name: string;
  sku: string;
  revenue: number;
  quantity: number;
  profit: number;
}

// --- Notifications ---

export interface Alert {
  id: string;
  type: "stock_critical" | "stock_low" | "sales_spike" | "sales_drop" | "high_returns";
  severity: "critical" | "warning" | "info";
  title: string;
  message: string;
  product_id?: string;
  product_name?: string;
  sku?: string;
  value?: number;
  threshold?: number;
  created_at: string;
}

export interface AlertsSummary {
  total: number;
  critical: number;
  warning: number;
  info: number;
}

export interface NotificationsData {
  alerts: Alert[];
  summary: AlertsSummary;
}

// --- Filters ---

export type PeriodKey = "today" | "7d" | "14d" | "30d" | "90d" | "180d" | "365d";

export const PERIOD_DAYS: Record<PeriodKey, number> = {
  today: 1,
  "7d": 7,
  "14d": 14,
  "30d": 30,
  "90d": 90,
  "180d": 180,
  "365d": 365,
};

export interface ProductFilters {
  category?: string;
  search?: string;
  sort?: string;
  order?: "asc" | "desc";
}

export interface SalesFilters {
  period?: PeriodKey;
  category?: string;
  page?: number;
  limit?: number;
}

// --- Sync ---

export interface SyncCredential {
  id: number;
  slug: string;
  name: string;
  api_base_url: string;
  marketplace_active: boolean;
  credential_id: number | null;
  credential_name: string | null;
  client_id: string | null;
  credential_active: boolean | null;
  connected_at: string | null;
  updated_at: string | null;
  status: "connected" | "disabled" | "not_connected";
  last_sync: {
    id: number;
    job_type: string;
    status: string;
    started_at: string | null;
    completed_at: string | null;
    records_processed: number;
    error_message: string | null;
  } | null;
}

export interface SyncHistoryItem {
  id: number;
  marketplace: string;
  marketplace_name: string;
  job_type: string;
  status: string;
  started_at: string | null;
  completed_at: string | null;
  records_processed: number;
  error_message: string | null;
  created_at: string;
  duration_sec: number | null;
}

export interface SyncJob {
  id: number;
  marketplace: string;
  marketplace_name: string;
  job_type: string;
  status: string;
  started_at?: string;
  completed_at?: string;
  records_processed: number;
  error_message?: string;
  created_at: string;
}

export interface SyncStatusResponse {
  data: SyncJob[];
  count: number;
}

// --- Auth ---

export interface UserInfo {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  role: string;
}

// --- Compatibility aliases ---
// These let existing page imports like "Product", "SalesResponse" etc. keep working.

export type Product = ProductListItem;
export type SaleItem = SaleRow;
export type SalesResponse = SalesPage;
export type InventoryItem = InventoryRow;
export type InventoryResponse = InventoryData;
export type NotificationAlert = Alert;
export type NotificationsResponse = NotificationsData;
