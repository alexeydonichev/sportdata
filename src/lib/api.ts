export type {
  DashboardData, DashboardChanges, ChartDataPoint,
  Category, Product, SaleItem, SalesResponse,
  InventoryItem, InventoryResponse,
  SyncCredential, SyncHistoryItem, SyncJob, SyncStatusResponse,
  NotificationAlert, NotificationsResponse,
  ProductDetail, MarketplaceStats, TopProduct, UserInfo,
} from "@/types/models";

import type {
  DashboardData, ChartDataPoint, Category, Product,
  SalesResponse, InventoryResponse, SyncCredential,
  SyncHistoryItem, SyncStatusResponse,
  NotificationsResponse, ProductDetail, UserInfo,
} from "@/types/models";

const API_URL = "";

class ApiClient {
  private token: string | null = null;

  constructor() {
    if (typeof window !== "undefined") this.token = localStorage.getItem("yf_token");
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
    if (!this.token && typeof window !== "undefined")
      this.token = localStorage.getItem("yf_token");
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
      method: "POST", body: JSON.stringify({ email, password }),
    });
    this.setToken(data.token);
    localStorage.setItem("yf_user", JSON.stringify(data.user));
    return data;
  }

  dashboard(params: { period?: string; category?: string; marketplace?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.period) qs.set("period", params.period);
    if (params.category) qs.set("category", params.category);
    if (params.marketplace) qs.set("marketplace", params.marketplace);
    return this.request<DashboardData>("/api/v1/dashboard?" + qs.toString());
  }

  chartData(params: { period?: string; category?: string; marketplace?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.period) qs.set("period", params.period);
    if (params.category) qs.set("category", params.category);
    if (params.marketplace) qs.set("marketplace", params.marketplace);
    return this.request<ChartDataPoint[]>("/api/v1/dashboard/chart?" + qs.toString());
  }

  categories() {
    return this.request<Category[]>("/api/v1/categories");
  }

  products(params: { category?: string; marketplace?: string; search?: string; sort?: string; order?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.category) qs.set("category", params.category);
    if (params.marketplace) qs.set("marketplace", params.marketplace);
    if (params.search) qs.set("search", params.search);
    if (params.sort) qs.set("sort", params.sort);
    if (params.order) qs.set("order", params.order);
    return this.request<Product[]>("/api/v1/products?" + qs.toString());
  }

  sales(params: { period?: string; category?: string; marketplace?: string; page?: number; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.period) qs.set("period", params.period);
    if (params.category) qs.set("category", params.category);
    if (params.marketplace) qs.set("marketplace", params.marketplace);
    if (params.page) qs.set("page", params.page.toString());
    if (params.limit) qs.set("limit", params.limit.toString());
    return this.request<SalesResponse>("/api/v1/sales?" + qs.toString());
  }

  inventory(params: { category?: string; marketplace?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.category) qs.set("category", params.category);
    if (params.marketplace) qs.set("marketplace", params.marketplace);
    return this.request<InventoryResponse>("/api/v1/inventory?" + qs.toString());
  }

  syncCredentials() { return this.request<SyncCredential[]>("/api/v1/sync/credentials"); }
  syncHistory() { return this.request<SyncHistoryItem[]>("/api/v1/sync/history"); }

  saveSyncCredential(data: { marketplace_id: number; name: string; api_key: string; client_id?: string }) {
    return this.request("/api/v1/sync/credentials", { method: "POST", body: JSON.stringify(data) });
  }

  pnl(params: { period?: string; category?: string; marketplace?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.period) qs.set("period", params.period);
    if (params.category) qs.set("category", params.category);
    if (params.marketplace) qs.set("marketplace", params.marketplace);
    return this.request<any>("/api/v1/analytics/pnl?" + qs.toString());
  }

  unitEconomics(params: { period?: string; sort?: string; order?: string; category?: string; marketplace?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.period) qs.set("period", params.period);
    if (params.sort) qs.set("sort", params.sort);
    if (params.order) qs.set("order", params.order);
    if (params.category) qs.set("category", params.category);
    if (params.marketplace) qs.set("marketplace", params.marketplace);
    return this.request<any>("/api/v1/analytics/unit-economics?" + qs.toString());
  }

  productDetail(id: string, period = "90d") {
    return this.request<ProductDetail>("/api/v1/products/" + id + "?period=" + period);
  }

  notifications() { return this.request<NotificationsResponse>("/api/v1/notifications"); }
  syncStatus() { return this.request<SyncStatusResponse>("/api/v1/sync/status"); }

  triggerSync(marketplace?: string) {
    return this.request<unknown>("/api/v1/sync/trigger", {
      method: "POST", body: JSON.stringify({ marketplace: marketplace || "" }),
    });
  }

  disconnectMarketplace(marketplaceId: number) {
    return this.request("/api/v1/sync/credentials?marketplace_id=" + marketplaceId, { method: "DELETE" });
  }
}

export const api = new ApiClient();
