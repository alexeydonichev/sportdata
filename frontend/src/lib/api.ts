export type {
  DashboardData, DashboardChanges, ChartDataPoint,
  Category, Product, SalesResponse,
  InventoryItem, InventoryResponse,
  SyncCredential, SyncHistoryItem,
  NotificationAlert, NotificationsResponse,
  ProductDetail, MarketplaceStats, TopProduct, UserInfo,
  ReturnsAnalytics, RNPItemsResponse, Manager, ChecklistTemplate,
  RNPDailyStat, RNPChecklistItem,
} from "@/types/models";

import type {
  DashboardData, ChartDataPoint, Category, Product,
  SalesResponse, InventoryResponse, SyncCredential,
  SyncHistoryItem, SyncStatusResponse,
  NotificationsResponse, ProductDetail, UserInfo,
  ReturnsAnalytics, RNPItemsResponse, Manager, ChecklistTemplate,
  RNPDailyStat, RNPChecklistItem,
} from "@/types/models";

const API_URL = typeof window !== "undefined" ? window.location.origin : "";

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
      const error = new Error(err.error || "HTTP " + res.status) as Error & { response?: { data?: { error?: string } } };
      error.response = { data: err };
      throw error;
    }
    return res.json();
  }

  async get<T = any>(url: string): Promise<{ data: T }> {
    const data = await this.request<T>(url);
    return { data };
  }

  async post<T = any>(url: string, body?: any): Promise<{ data: T }> {
    const data = await this.request<T>(url, { method: "POST", body: body ? JSON.stringify(body) : undefined });
    return { data };
  }

  async patch<T = any>(url: string, body?: any): Promise<{ data: T }> {
    const data = await this.request<T>(url, { method: "PATCH", body: body ? JSON.stringify(body) : undefined });
    return { data };
  }

  async delete<T = any>(url: string): Promise<{ data: T }> {
    const data = await this.request<T>(url, { method: "DELETE" });
    return { data };
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

  categories() { return this.request<Category[]>("/api/v1/categories"); }

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

  updateProduct(id: string, data: { cost_price?: number; name?: string }) {
    return this.request<{ product: { id: string; name: string; sku: string; cost_price: number } }>(
      "/api/v1/products/" + id, { method: "PATCH", body: JSON.stringify(data) }
    );
  }

  bulkUpdateCostPrice(items: { id?: string; sku?: string; cost_price: number }[]) {
    return this.request<{ updated: number; errors: string[] }>(
      "/api/v1/products/bulk-cost", { method: "POST", body: JSON.stringify({ items }) }
    );
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

  returnsAnalytics(params: { period?: string; category?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.period) qs.set("period", params.period);
    if (params.category) qs.set("category", params.category);
    return this.request<ReturnsAnalytics>("/api/v1/analytics/returns?" + qs.toString());
  }

  // === РНП методы ===
  rnpManagers() {
    return this.request<{ managers: Manager[] }>("/api/v1/rnp/managers");
  }

  rnpChecklistTemplates() {
    return this.request<{ templates: ChecklistTemplate[] }>("/api/v1/rnp/checklist-templates");
  }

  rnpTemplates(params: { year?: number; month?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.year) qs.set("year", params.year.toString());
    if (params.month) qs.set("month", params.month.toString());
    return this.request<any>("/api/v1/rnp/templates?" + qs.toString());
  }

  rnpItems(templateId: number) {
    return this.request<RNPItemsResponse>("/api/v1/rnp/templates/" + templateId);
  }

  rnpUpdateItem(itemId: number, data: { manager_id?: number | null; item_status?: string }) {
    return this.request<{ message: string }>("/api/v1/rnp/items/" + itemId, {
      method: "PATCH", body: JSON.stringify(data),
    });
  }

  rnpItemDaily(itemId: number) {
    return this.request<{ stats: RNPDailyStat[] }>("/api/v1/rnp/items/" + itemId + "/daily");
  }

  rnpItemChecklist(itemId: number) {
    return this.request<{ checklist: RNPChecklistItem[] }>("/api/v1/rnp/items/" + itemId + "/checklist");
  }

  rnpInitChecklist(itemId: number) {
    return this.request<{ message: string }>("/api/v1/rnp/items/" + itemId + "/checklist/init", {
      method: "POST",
    });
  }

  rnpUpdateChecklist(checklistId: number, data: { is_done: boolean; comment?: string }) {
    return this.request<{ message: string }>("/api/v1/rnp/checklist/" + checklistId, {
      method: "PATCH", body: JSON.stringify(data),
    });
  }

  register(data: { token: string; password: string; name: string }) {
    return this.request<{ token: string; user: UserInfo }>("/api/v1/auth/register", {
      method: "POST", body: JSON.stringify(data),
    });
  }
}

export interface AdminScope { scope_type: string; scope_value: string | null; }
export interface AdminUser {
  id: number; email: string; name: string | null; role: string; role_level: number;
  is_active: boolean; invited_by: number | null; inviter_email: string | null;
  last_login_at: string | null; created_at: string; scopes: AdminScope[];
}
export interface AdminInvite {
  id: number; token: string; email: string; role_level: number; role_name: string;
  scopes: AdminScope[]; created_by: number; creator_email: string;
  expires_at: string; used_at: string | null; created_at: string;
}

export const api = new ApiClient();
