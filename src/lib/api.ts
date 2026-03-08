const API_URL = "";

class ApiClient {
  private token: string | null = null;

  constructor() {
    if (typeof window !== "undefined") {
      this.token = localStorage.getItem("yf_token");
    }
  }

  setToken(token: string) {
    this.token = token;
    localStorage.setItem("yf_token", token);
  }

  clearToken() {
    this.token = null;
    localStorage.removeItem("yf_token");
    localStorage.removeItem("yf_user");
  }

  getToken() {
    if (!this.token && typeof window !== "undefined") {
      this.token = localStorage.getItem("yf_token");
    }
    return this.token;
  }

  async request<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    const token = this.getToken();
    if (token) headers["Authorization"] = "Bearer " + token;

    const res = await fetch(API_URL + endpoint, { ...options, headers: { ...headers, ...options.headers } });

    if (res.status === 401) {
      this.clearToken();
      if (typeof window !== "undefined") window.location.href = "/login";
      throw new Error("Unauthorized");
    }
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || "HTTP " + res.status);
    }
    return res.json();
  }

  async login(email: string, password: string) {
    const data = await this.request<{ token: string; user: UserInfo }>("/api/v1/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
    this.setToken(data.token);
    localStorage.setItem("yf_user", JSON.stringify(data.user));
    return data;
  }

  dashboard(period = "7d") {
    return this.request<DashboardData>("/api/v1/dashboard?period=" + period);
  }

  chartData(period = "7d") {
    return this.request<ChartDataPoint[]>("/api/v1/dashboard/chart?period=" + period);
  }

  categories() {
    return this.request<Category[]>("/api/v1/categories");
  }

  products(params: { category?: string; search?: string; sort?: string; order?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.category) qs.set("category", params.category);
    if (params.search) qs.set("search", params.search);
    if (params.sort) qs.set("sort", params.sort);
    if (params.order) qs.set("order", params.order);
    return this.request<Product[]>("/api/v1/products?" + qs.toString());
  }

  sales(params: { period?: string; category?: string; page?: number; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.period) qs.set("period", params.period);
    if (params.category) qs.set("category", params.category);
    if (params.page) qs.set("page", params.page.toString());
    if (params.limit) qs.set("limit", params.limit.toString());
    return this.request<SalesResponse>("/api/v1/sales?" + qs.toString());
  }

  inventory(params: { category?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.category) qs.set("category", params.category);
    return this.request<InventoryResponse>("/api/v1/inventory?" + qs.toString());
  }

  syncCredentials() {
    return this.request<SyncCredential[]>("/api/v1/sync/credentials");
  }

  syncHistory() {
    return this.request<SyncHistoryItem[]>("/api/v1/sync/history");
  }

  saveSyncCredential(data: { marketplace_id: number; name: string; api_key: string; client_id?: string }) {
    return this.request("/api/v1/sync/credentials", {
      method: "POST",
      body: JSON.stringify(data),
    });
  }



  productDetail(id: string, period = "90d") {
    return this.request<ProductDetail>("/api/v1/products/" + id + "?period=" + period);
  }

  notifications() {
    return this.request<NotificationsResponse>("/api/v1/notifications");
  }

  syncStatus() {
    return this.request<SyncStatusResponse>("/api/v1/sync/status");
  }

  triggerSync(marketplace?: string) {
    return this.request<any>("/api/v1/sync/trigger", {
      method: "POST",
      body: JSON.stringify({ marketplace: marketplace || "" }),
    });
  }

  disconnectMarketplace(marketplaceId: number) {
    return this.request("/api/v1/sync/credentials?marketplace_id=" + marketplaceId, { method: "DELETE" });
  }
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

export const api = new ApiClient();

// Types
export interface ChartDataPoint { date: string; revenue: number; profit: number; orders: number; quantity: number; }
export interface UserInfo { id: string; email: string; first_name: string; last_name: string; role: string; }

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
  period: string; date_from: string; date_to: string;
  total_revenue: number; total_profit: number; total_orders: number;
  total_quantity: number; total_sku: number; avg_order_value: number;
  profit_margin_pct: number; total_commission: number; total_logistics: number;
  changes: DashboardChanges;
  by_marketplace: MarketplaceStats[]; top_products: TopProduct[] | null;
}

export interface MarketplaceStats { marketplace: string; name: string; revenue: number; profit: number; quantity: number; share_pct: number; }
export interface TopProduct { product_id: string; name: string; sku: string; revenue: number; quantity: number; profit: number; }

export interface Category { slug: string; name: string; product_count: number; revenue: number; }

export interface Product {
  id: string; name: string; sku: string; avg_price: number; cost_price: number;
  category: string; category_slug: string;
  revenue: number; profit: number; quantity: number; orders: number; margin_pct: number;
  stock: number; returns: number; return_pct: number;
}

export interface SaleItem {
  id: string; date: string; product_name: string; sku: string; category: string;
  quantity: number; revenue: number; profit: number; commission: number; logistics: number; marketplace: string;
}

export interface SalesResponse { items: SaleItem[]; total: number; page: number; limit: number; pages: number; }

export interface InventoryItem {
  product_id: string; name: string; sku: string; category: string;
  warehouse: string; stock: number; avg_daily_sales: number; days_of_stock: number;
}

export interface InventoryResponse { items: InventoryItem[]; summary: { total_stock: number; products_in_stock: number; warehouses: number; }; }

export interface SyncCredential {
  id: number; slug: string; name: string; api_base_url: string;
  marketplace_active: boolean; credential_id: number | null;
  credential_name: string | null; client_id: string | null;
  credential_active: boolean | null; connected_at: string | null;
  updated_at: string | null; status: "connected" | "disabled" | "not_connected";
  last_sync: { id: number; job_type: string; status: string; started_at: string | null; completed_at: string | null; records_processed: number; error_message: string | null; } | null;
}

export interface SyncHistoryItem {
  id: number; marketplace: string; marketplace_name: string;
  job_type: string; status: string; started_at: string | null;
  completed_at: string | null; records_processed: number;
  error_message: string | null; created_at: string; duration_sec: number | null;
}

export interface NotificationAlert {
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

export interface NotificationsResponse {
  alerts: NotificationAlert[];
  summary: { total: number; critical: number; warning: number; info: number };
}

export interface ProductDetail {
  product: {
    id: string; name: string; sku: string; barcode: string;
    cost_price: number; price: number;
    category: string; category_slug: string; created_at: string;
  };
  metrics: {
    total_revenue: number; total_profit: number; total_sold: number;
    total_orders: number; avg_price: number; total_commission: number;
    total_logistics: number; total_returns: number;
    margin_pct: number; return_pct: number;
  };
  changes: { revenue: number | null; profit: number | null; quantity: number | null; orders: number | null };
  chart: { date: string; revenue: number; profit: number; quantity: number; orders: number }[];
  inventory: {
    items: { warehouse: string; stock: number; updated_at: string }[];
    total_stock: number; avg_daily_sales: number; days_of_stock: number;
  };
  abc: { grade: "A" | "B" | "C"; revenue_share: number };
  by_marketplace: { marketplace: string; name: string; revenue: number; profit: number; quantity: number }[];
}