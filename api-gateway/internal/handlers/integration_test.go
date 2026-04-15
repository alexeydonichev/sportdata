//go:build integration

package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"sportdata/api-gateway/internal/middleware"
)

var testDB *pgxpool.Pool
var testHandler *Handler

func TestMain(m *testing.M) {
	gin.SetMode(gin.TestMode)
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = os.Getenv("DATABASE_URL")
	}
	if dsn == "" {
		os.Exit(0)
	}

	os.Setenv("JWT_SECRET", "integration-test-secret")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	var err error
	testDB, err = pgxpool.New(ctx, dsn)
	if err != nil {
		panic("pgxpool.New: " + err.Error())
	}
	if err := testDB.Ping(ctx); err != nil {
		panic("DB ping: " + err.Error())
	}
	defer testDB.Close()
	testHandler = New(testDB, nil)
	os.Exit(m.Run())
}

func withAuth() *gin.Engine {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", "fabdd651-1f33-4681-a4eb-277e650ceded")
		c.Set("user_email", "test@test.com")
		c.Set("user_role", "superadmin")
		c.Set("user_level", 0)
		c.Set("role_level", 0)
		c.Set("user_hidden", true)
		c.Next()
	})
	return r
}

func doGET(t *testing.T, r *gin.Engine, path string) *httptest.ResponseRecorder {
	t.Helper()
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", path, nil)
	r.ServeHTTP(w, req)
	return w
}

func doPOST(t *testing.T, r *gin.Engine, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	return w
}

func doDELETE(t *testing.T, r *gin.Engine, path string) *httptest.ResponseRecorder {
	t.Helper()
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", path, nil)
	r.ServeHTTP(w, req)
	return w
}

func doPUT(t *testing.T, r *gin.Engine, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	return w
}

func expectCode(t *testing.T, name string, w *httptest.ResponseRecorder, want int) {
	t.Helper()
	if w.Code != want {
		body := w.Body.String()
		if len(body) > 300 {
			body = body[:300]
		}
		t.Errorf("%s: got %d, want %d: %s", name, w.Code, want, body)
	}
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// ── Health ───────────────────────────────────────────────────────────

func TestIntegration_Health(t *testing.T) {
	r := gin.New()
	r.GET("/health", testHandler.Health)
	w := doGET(t, r, "/health")
	t.Logf("Health: %d %s", w.Code, w.Body.String())
	expectCode(t, "Health", w, 200)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["postgres"] != true {
		t.Error("postgres should be true")
	}
}

func TestIntegration_HealthDetails(t *testing.T) {
	r := gin.New()
	r.GET("/health", testHandler.Health)
	w := doGET(t, r, "/health")

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)

	for _, field := range []string{"service", "version", "postgres", "time", "status"} {
		if resp[field] == nil {
			t.Errorf("Health missing field: %s", field)
		}
	}
	t.Logf("Health: service=%v version=%v status=%v postgres=%v",
		resp["service"], resp["version"], resp["status"], resp["postgres"])
}

// ── Auth ─────────────────────────────────────────────────────────────

func TestIntegration_LoginBadRequest(t *testing.T) {
	r := gin.New()
	r.POST("/login", testHandler.Login)

	w := doPOST(t, r, "/login", "{}")
	t.Logf("Login empty: %d %s", w.Code, w.Body.String())
	expectCode(t, "login empty", w, 400)

	w2 := doPOST(t, r, "/login", `{"email":"nobody@x.com","password":"wrong123"}`)
	t.Logf("Login bad creds: %d %s", w2.Code, w2.Body.String())
	expectCode(t, "login bad creds", w2, 401)
}

func TestIntegration_AuthFlow(t *testing.T) {
	os.Setenv("JWT_SECRET", "integration-test-secret")
	tok, _ := middleware.GenerateToken(middleware.Claims{
		UserID: "1", Email: "t@t.com", Role: "admin", Level: 2,
	})
	r := gin.New()
	r.Use(middleware.AuthRequired())
	r.GET("/me", func(c *gin.Context) {
		uid, _ := c.Get("user_id")
		c.JSON(200, gin.H{"user_id": uid})
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/me", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	r.ServeHTTP(w, req)
	expectCode(t, "auth flow", w, 200)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["user_id"] != "1" {
		t.Errorf("uid = %v", resp["user_id"])
	}
}

// ── References ───────────────────────────────────────────────────────

func TestIntegration_Categories(t *testing.T) {
	r := withAuth()
	r.GET("/cat", testHandler.GetCategories)
	w := doGET(t, r, "/cat")
	t.Logf("Categories: %d %s", w.Code, w.Body.String())
	expectCode(t, "Categories", w, 200)
}

func TestIntegration_CategoriesNoAuth(t *testing.T) {
	r := gin.New()
	r.GET("/cat", testHandler.GetCategories)
	w := doGET(t, r, "/cat")
	expectCode(t, "Categories no auth", w, 200)
}

func TestIntegration_Marketplaces(t *testing.T) {
	r := withAuth()
	r.GET("/mp", testHandler.GetMarketplaces)
	w := doGET(t, r, "/mp")
	t.Logf("Marketplaces: %d %s", w.Code, w.Body.String())
	expectCode(t, "Marketplaces", w, 200)
}

// ── Dashboard ────────────────────────────────────────────────────────

func TestIntegration_Dashboard(t *testing.T) {
	r := withAuth()
	r.GET("/d", testHandler.GetDashboard)

	w := doGET(t, r, "/d")
	t.Logf("Dashboard default: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Dashboard", w, 200)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if len(resp) == 0 {
		t.Error("Dashboard returned empty JSON")
	}

	for _, period := range []string{"7d", "30d", "90d"} {
		w2 := doGET(t, r, "/d?period="+period)
		expectCode(t, "Dashboard "+period, w2, 200)
	}
}

func TestIntegration_DashboardChart(t *testing.T) {
	r := withAuth()
	r.GET("/dc", testHandler.GetDashboardChart)

	for _, period := range []string{"7d", "30d", "90d"} {
		w := doGET(t, r, "/dc?period="+period)
		t.Logf("DashboardChart %s: %d (%d bytes)", period, w.Code, w.Body.Len())
		expectCode(t, "DashboardChart "+period, w, 200)
	}
}

// ── Sales ────────────────────────────────────────────────────────────

func TestIntegration_Sales(t *testing.T) {
	r := withAuth()
	r.GET("/s", testHandler.GetSales)
	w := doGET(t, r, "/s?period=30d&limit=5")
	t.Logf("Sales: %d %s", w.Code, w.Body.String())
	expectCode(t, "Sales", w, 200)
}

func TestIntegration_SalesFilters(t *testing.T) {
	r := withAuth()
	r.GET("/s", testHandler.GetSales)

	tests := []struct {
		name  string
		query string
	}{
		{"default", "/s"},
		{"period 7d", "/s?period=7d"},
		{"limit", "/s?limit=2"},
		{"page", "/s?page=1&limit=5"},
		{"marketplace", "/s?marketplace=wildberries&limit=3"},
		{"category", "/s?category_id=34&limit=3"},
		{"combined", "/s?period=30d&marketplace=wildberries&limit=2"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doGET(t, r, tt.query)
			expectCode(t, tt.name, w, 200)
		})
	}
}

// ── Products ─────────────────────────────────────────────────────────

func TestIntegration_Products(t *testing.T) {
	r := withAuth()
	r.GET("/p", testHandler.GetProducts)

	w := doGET(t, r, "/p?limit=3")
	t.Logf("Products: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Products", w, 200)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["limit"] == nil {
		t.Error("Products: missing 'limit'")
	}
	if resp["total"] == nil {
		t.Error("Products: missing 'total'")
	}

	w2 := doGET(t, r, "/p?limit=2&marketplace=wildberries")
	expectCode(t, "Products filtered", w2, 200)
}

func TestIntegration_ProductByID(t *testing.T) {
	r := withAuth()
	r.GET("/p/:id", testHandler.GetProduct)

	w := doGET(t, r, "/p/999999")
	t.Logf("Product 999999: %d", w.Code)

	w2 := doGET(t, r, "/p/1")
	t.Logf("Product 1: %d (%d bytes)", w2.Code, w2.Body.Len())
}

// ── Export ────────────────────────────────────────────────────────────

func TestIntegration_SalesExport(t *testing.T) {
	r := withAuth()
	r.GET("/export", testHandler.ExportSales)

	w := doGET(t, r, "/export?period=7d&limit=10")
	t.Logf("ExportSales: %d, CT=%s, Size=%d", w.Code, w.Header().Get("Content-Type"), w.Body.Len())
	expectCode(t, "ExportSales", w, 200)

	b := w.Body.Bytes()
	if len(b) > 2 && b[0] == 0x50 && b[1] == 0x4B {
		t.Log("ExportSales: valid XLSX")
	} else {
		t.Error("ExportSales: not a valid XLSX")
	}
}

func TestIntegration_ProductsExport(t *testing.T) {
	r := withAuth()
	r.GET("/export-products", testHandler.ExportProducts)

	w := doGET(t, r, "/export-products?limit=10")
	t.Logf("ExportProducts: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "ExportProducts", w, 200)
}

func TestIntegration_AnalyticsExport(t *testing.T) {
	r := withAuth()
	r.GET("/export-analytics", testHandler.ExportAnalytics)

	w := doGET(t, r, "/export-analytics?period=30d")
	t.Logf("ExportAnalytics: %d (%d bytes)", w.Code, w.Body.Len())
}

// ── Notifications ────────────────────────────────────────────────────

func TestIntegration_Notifications(t *testing.T) {
	r := withAuth()
	r.GET("/n", testHandler.GetNotifications)

	w := doGET(t, r, "/n")
	t.Logf("Notifications: %d %s", w.Code, w.Body.String())
	expectCode(t, "Notifications", w, 200)
}

func TestIntegration_NotificationsFilter(t *testing.T) {
	r := withAuth()
	r.GET("/n", testHandler.GetNotifications)

	w1 := doGET(t, r, "/n")
	expectCode(t, "Notifications all", w1, 200)

	var all map[string]interface{}
	json.Unmarshal(w1.Body.Bytes(), &all)

	summary, _ := all["summary"].(map[string]interface{})
	if summary != nil {
		t.Logf("Alerts: total=%v critical=%v warning=%v",
			summary["total"], summary["critical"], summary["warning"])
	}

	w2 := doGET(t, r, "/n?severity=critical")
	expectCode(t, "Notifications critical", w2, 200)
}

// ── Trends ───────────────────────────────────────────────────────────

func TestIntegration_Trends(t *testing.T) {
	r := withAuth()
	r.GET("/trends", testHandler.GetTrends)

	for _, period := range []string{"7d", "30d", "90d"} {
		w := doGET(t, r, "/trends?period="+period)
		t.Logf("Trends %s: %d (%d bytes)", period, w.Code, w.Body.Len())
		expectCode(t, "Trends "+period, w, 200)
	}
}

// ── Inventory ────────────────────────────────────────────────────────

func TestIntegration_Inventory(t *testing.T) {
	r := withAuth()
	r.GET("/inv", testHandler.GetInventory)

	w := doGET(t, r, "/inv?limit=5")
	t.Logf("Inventory: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Inventory", w, 200)
}

// ── Sync ─────────────────────────────────────────────────────────────

func TestIntegration_SyncStatus(t *testing.T) {
	r := withAuth()
	r.GET("/sync/status", testHandler.GetSyncStatus)

	w := doGET(t, r, "/sync/status")
	t.Logf("SyncStatus: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "SyncStatus", w, 200)
}

func TestIntegration_SyncCredentials(t *testing.T) {
	r := withAuth()
	r.GET("/sync/credentials", testHandler.GetSyncCredentials)

	w := doGET(t, r, "/sync/credentials")
	t.Logf("SyncCredentials: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "SyncCredentials", w, 200)
}

func TestIntegration_SyncHistory(t *testing.T) {
	r := withAuth()
	r.GET("/sync/history", testHandler.GetSyncHistory)

	w := doGET(t, r, "/sync/history")
	t.Logf("SyncHistory: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "SyncHistory", w, 200)
}

func TestIntegration_SaveDeleteCredential(t *testing.T) {
	r := withAuth()
	r.POST("/sync/credentials", testHandler.SaveSyncCredential)
	r.DELETE("/sync/credentials/:marketplace", testHandler.DeleteSyncCredential)

	w1 := doPOST(t, r, "/sync/credentials", `{"marketplace":"test_mp","api_key":"test_key_123"}`)
	t.Logf("SaveCredential: %d %s", w1.Code, w1.Body.String())

	w2 := doDELETE(t, r, "/sync/credentials/test_mp")
	t.Logf("DeleteCredential: %d %s", w2.Code, w2.Body.String())
}

func TestIntegration_TriggerSync(t *testing.T) {
	r := withAuth()
	r.POST("/sync/trigger", testHandler.TriggerSync)

	w := doPOST(t, r, "/sync/trigger", `{"marketplace":"wildberries"}`)
	body := w.Body.String()
	if len(body) > 200 {
		body = body[:200]
	}
	t.Logf("TriggerSync: %d %s", w.Code, body)
}

// ── Supplier ─────────────────────────────────────────────────────────

func TestIntegration_SupplierSales(t *testing.T) {
	r := withAuth()
	r.GET("/supplier/sales", testHandler.GetSupplierSales)

	w := doGET(t, r, "/supplier/sales?period=7d")
	t.Logf("SupplierSales: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "SupplierSales", w, 200)
}

func TestIntegration_SupplierStocks(t *testing.T) {
	r := withAuth()
	r.GET("/supplier/stocks", testHandler.GetSupplierStocks)

	w := doGET(t, r, "/supplier/stocks")
	t.Logf("SupplierStocks: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "SupplierStocks", w, 200)
}

// ── Admin ────────────────────────────────────────────────────────────

func TestIntegration_AdminUsers(t *testing.T) {
	r := withAuth()
	r.GET("/admin/users", testHandler.GetUsers)

	w := doGET(t, r, "/admin/users")
	t.Logf("AdminUsers: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "AdminUsers", w, 200)
}

func TestIntegration_AdminRoles(t *testing.T) {
	r := withAuth()
	r.GET("/admin/roles", testHandler.GetRoles)

	w := doGET(t, r, "/admin/roles")
	t.Logf("AdminRoles: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "AdminRoles", w, 200)
}

func TestIntegration_AdminDepartments(t *testing.T) {
	r := withAuth()
	r.GET("/admin/departments", testHandler.GetDepartments)

	w := doGET(t, r, "/admin/departments")
	t.Logf("AdminDepartments: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "AdminDepartments", w, 200)
}

func TestIntegration_AdminAuditLog(t *testing.T) {
	r := withAuth()
	r.GET("/admin/audit", testHandler.GetAuditLog)

	w := doGET(t, r, "/admin/audit")
	t.Logf("AuditLog: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "AuditLog", w, 200)
}

func TestIntegration_AdminSystemInfo(t *testing.T) {
	r := withAuth()
	r.GET("/admin/system", testHandler.GetSystemInfo)

	w := doGET(t, r, "/admin/system")
	t.Logf("SystemInfo: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "SystemInfo", w, 200)
}

func TestIntegration_AdminAllUsers(t *testing.T) {
	r := withAuth()
	r.GET("/admin/all-users", testHandler.GetAllUsersIncludingHidden)

	w := doGET(t, r, "/admin/all-users")
	t.Logf("AllUsers: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "AllUsers", w, 200)
}

// ── Analytics ────────────────────────────────────────────────────────

func TestIntegration_Analytics(t *testing.T) {
	r := withAuth()
	r.GET("/analytics", testHandler.GetAnalytics)

	for _, period := range []string{"7d", "30d"} {
		w := doGET(t, r, "/analytics?period="+period)
		t.Logf("Analytics %s: %d (%d bytes)", period, w.Code, w.Body.Len())
		expectCode(t, "Analytics "+period, w, 200)
	}
}

func TestIntegration_AnalyticsOptimized(t *testing.T) {
	r := withAuth()
	r.GET("/ao", testHandler.GetAnalyticsOptimized)

	w := doGET(t, r, "/ao?period=30d")
	t.Logf("AnalyticsOptimized: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "AnalyticsOptimized", w, 200)
}

func TestIntegration_AnalyticsABC(t *testing.T) {
	r := withAuth()
	r.GET("/abc", testHandler.GetAnalyticsABC)

	w := doGET(t, r, "/abc?period=30d")
	t.Logf("AnalyticsABC: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "AnalyticsABC", w, 200)
}

func TestIntegration_AnalyticsBrands(t *testing.T) {
	r := withAuth()
	r.GET("/brands", testHandler.GetBrandsAnalytics)

	w := doGET(t, r, "/brands?period=30d")
	t.Logf("BrandsAnalytics: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "BrandsAnalytics", w, 200)
}

func TestIntegration_AnalyticsCategories(t *testing.T) {
	r := withAuth()
	r.GET("/cat-analytics", testHandler.GetCategoriesAnalytics)

	w := doGET(t, r, "/cat-analytics?period=30d")
	t.Logf("CategoriesAnalytics: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "CategoriesAnalytics", w, 200)
}

func TestIntegration_AnalyticsProducts(t *testing.T) {
	r := withAuth()
	r.GET("/prod-analytics", testHandler.GetProductsAnalytics)

	w := doGET(t, r, "/prod-analytics?period=30d")
	t.Logf("ProductsAnalytics: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "ProductsAnalytics", w, 200)
}

func TestIntegration_AnalyticsGeography(t *testing.T) {
	r := withAuth()
	r.GET("/geo", testHandler.GetGeography)

	w := doGET(t, r, "/geo?period=30d")
	t.Logf("Geography: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Geography", w, 200)
}

func TestIntegration_AnalyticsWarehouses(t *testing.T) {
	r := withAuth()
	r.GET("/wh", testHandler.GetWarehousesAnalytics)

	w := doGET(t, r, "/wh?period=30d")
	t.Logf("Warehouses: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Warehouses", w, 200)
}

func TestIntegration_AnalyticsTrending(t *testing.T) {
	r := withAuth()
	r.GET("/trending", testHandler.GetTrending)

	w := doGET(t, r, "/trending?period=30d")
	t.Logf("Trending: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Trending", w, 200)
}

func TestIntegration_AnalyticsPnL(t *testing.T) {
	r := withAuth()
	r.GET("/pnl", testHandler.GetPnLFull)

	w := doGET(t, r, "/pnl?period=30d")
	t.Logf("PnL: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "PnL", w, 200)
}

func TestIntegration_AnalyticsFinance(t *testing.T) {
	r := withAuth()
	r.GET("/finance", testHandler.GetFinanceFull)

	w := doGET(t, r, "/finance?period=30d")
	t.Logf("Finance: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Finance", w, 200)
}

func TestIntegration_AnalyticsUnitEconomics(t *testing.T) {
	r := withAuth()
	r.GET("/ue", testHandler.GetUnitEconomicsFull)

	w := doGET(t, r, "/ue?period=30d")
	t.Logf("UnitEconomics: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "UnitEconomics", w, 200)
}

func TestIntegration_AnalyticsRNP(t *testing.T) {
	r := withAuth()
	r.GET("/rnp-analytics", testHandler.GetAnalyticsRNP)

	w := doGET(t, r, "/rnp-analytics?period=30d")
	t.Logf("AnalyticsRNP: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "AnalyticsRNP", w, 200)
}

func TestIntegration_ReturnsAnalytics(t *testing.T) {
	r := withAuth()
	r.GET("/returns", testHandler.GetReturnsAnalytics)

	w := doGET(t, r, "/returns?period=30d")
	t.Logf("Returns: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Returns", w, 200)
}

// ── Profile ──────────────────────────────────────────────────────────

func TestIntegration_GetMe(t *testing.T) {
	r := withAuth()
	r.GET("/me", testHandler.GetMe)

	w := doGET(t, r, "/me")
	t.Logf("GetMe: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "GetMe", w, 200)
}

func TestIntegration_GetProfile(t *testing.T) {
	r := withAuth()
	r.GET("/profile", testHandler.GetProfile)

	w := doGET(t, r, "/profile")
	t.Logf("GetProfile: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "GetProfile", w, 200)
}

func TestIntegration_ChangePasswordBadRequest(t *testing.T) {
	r := withAuth()
	r.POST("/change-password", testHandler.ChangePassword)

	w := doPOST(t, r, "/change-password", `{}`)
	t.Logf("ChangePassword empty: %d %s", w.Code, w.Body.String())
	if w.Code == 200 {
		t.Error("ChangePassword with empty body should not return 200")
	}
}

// ── Invites ──────────────────────────────────────────────────────────

func TestIntegration_Invites(t *testing.T) {
	r := withAuth()
	r.GET("/invites", testHandler.GetInvites)

	w := doGET(t, r, "/invites")
	t.Logf("Invites: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "Invites", w, 200)
}

func TestIntegration_CreateInviteBadRequest(t *testing.T) {
	r := withAuth()
	r.POST("/invites", testHandler.CreateInvite)

	w := doPOST(t, r, "/invites", `{}`)
	t.Logf("CreateInvite empty: %d %s", w.Code, w.Body.String())
}

// ── RNP ──────────────────────────────────────────────────────────────

func TestIntegration_RNPTemplates(t *testing.T) {
	r := withAuth()
	r.GET("/rnp/templates", testHandler.GetRNPTemplates)

	w := doGET(t, r, "/rnp/templates")
	t.Logf("RNPTemplates: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "RNPTemplates", w, 200)
}

func TestIntegration_RNPProjects(t *testing.T) {
	r := withAuth()
	r.GET("/rnp/projects", testHandler.GetProjects)

	w := doGET(t, r, "/rnp/projects")
	t.Logf("RNPProjects: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "RNPProjects", w, 200)
}

func TestIntegration_RNPManagers(t *testing.T) {
	r := withAuth()
	r.GET("/rnp/managers", testHandler.GetManagers)

	w := doGET(t, r, "/rnp/managers")
	t.Logf("RNPManagers: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "RNPManagers", w, 200)
}

func TestIntegration_RNPItems(t *testing.T) {
	r := withAuth()
	r.GET("/rnp/items/:id", testHandler.GetRNPItems)

	w := doGET(t, r, "/rnp/items/1")
	t.Logf("RNPItems: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "RNPItems", w, 200)
}

func TestIntegration_RNPDailyStats(t *testing.T) {
	r := withAuth()
	r.GET("/rnp/daily-stats", testHandler.GetRNPDailyStats)

	w := doGET(t, r, "/rnp/daily-stats")
	t.Logf("RNPDailyStats: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "RNPDailyStats", w, 200)
}

func TestIntegration_RNPChecklist(t *testing.T) {
	r := withAuth()
	r.GET("/rnp/checklist", testHandler.GetRNPChecklist)

	w := doGET(t, r, "/rnp/checklist")
	t.Logf("RNPChecklist: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "RNPChecklist", w, 200)
}

func TestIntegration_ChecklistTemplates(t *testing.T) {
	r := withAuth()
	r.GET("/rnp/checklist-templates", testHandler.GetChecklistTemplates)

	w := doGET(t, r, "/rnp/checklist-templates")
	t.Logf("ChecklistTemplates: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "ChecklistTemplates", w, 200)
}

func TestIntegration_CreateRNPTemplate(t *testing.T) {
	r := withAuth()
	r.POST("/rnp/templates", testHandler.CreateRNPTemplate)

	w := doPOST(t, r, "/rnp/templates", `{"name":"test_template","description":"test"}`)
	t.Logf("CreateRNPTemplate: %d %s", w.Code, w.Body.String())
}

func TestIntegration_CreateRNPItem(t *testing.T) {
	r := withAuth()
	r.POST("/rnp/items", testHandler.CreateRNPItem)

	w := doPOST(t, r, "/rnp/items", `{}`)
	t.Logf("CreateRNPItem empty: %d %s", w.Code, w.Body.String())
}

// ── Products Extra ───────────────────────────────────────────────────

func TestIntegration_ProductDetail(t *testing.T) {
	r := withAuth()
	r.GET("/product-detail/:id", testHandler.GetProductDetail)

	w := doGET(t, r, "/product-detail/1")
	t.Logf("ProductDetail: %d (%d bytes)", w.Code, w.Body.Len())
}

func TestIntegration_UpdateProduct(t *testing.T) {
	r := withAuth()
	r.PUT("/products/:id", testHandler.UpdateProduct)

	w := doPUT(t, r, "/products/1", `{"cost_price":100}`)
	t.Logf("UpdateProduct: %d %s", w.Code, w.Body.String())
}

func TestIntegration_BulkUpdateCostPrice(t *testing.T) {
	r := withAuth()
	r.POST("/products/bulk-cost", testHandler.BulkUpdateCostPrice)

	w := doPOST(t, r, "/products/bulk-cost", `{"items":[]}`)
	t.Logf("BulkUpdateCostPrice: %d %s", w.Code, w.Body.String())
}

func TestIntegration_GetPnL(t *testing.T) {
	r := withAuth()
	r.GET("/pnl-short", testHandler.GetPnL)

	w := doGET(t, r, "/pnl-short?period=30d")
	t.Logf("GetPnL short: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "GetPnL", w, 200)
}

func TestIntegration_GetABC(t *testing.T) {
	r := withAuth()
	r.GET("/abc-short", testHandler.GetABC)

	w := doGET(t, r, "/abc-short?period=30d")
	t.Logf("GetABC short: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "GetABC", w, 200)
}

func TestIntegration_GetUnitEconomics(t *testing.T) {
	r := withAuth()
	r.GET("/ue-short", testHandler.GetUnitEconomics)

	w := doGET(t, r, "/ue-short?period=30d")
	t.Logf("GetUnitEconomics short: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "GetUnitEconomics", w, 200)
}

func TestIntegration_GetFinance(t *testing.T) {
	r := withAuth()
	r.GET("/finance-short", testHandler.GetFinance)

	w := doGET(t, r, "/finance-short?period=30d")
	t.Logf("GetFinance short: %d (%d bytes)", w.Code, w.Body.Len())
	expectCode(t, "GetFinance", w, 200)
}

// ── Admin CRUD ───────────────────────────────────────────────────────

func TestIntegration_AdminCreateDeleteUser(t *testing.T) {
	r := withAuth()
	r.POST("/admin/users", testHandler.CreateUser)
	r.DELETE("/admin/users/:id", testHandler.DeleteUser)

	w1 := doPOST(t, r, "/admin/users", `{"email":"integration_test_user@test.com","password":"TestPass123!","role":"viewer","name":"IntTest"}`)
	t.Logf("CreateUser: %d %s", w1.Code, w1.Body.String())

	if w1.Code == 200 || w1.Code == 201 {
		var resp map[string]interface{}
		json.Unmarshal(w1.Body.Bytes(), &resp)
		if id, ok := resp["id"]; ok {
			t.Logf("Created user id=%v, cleaning up", id)
			idStr := ""
			switch v := id.(type) {
			case float64:
				idStr = strings.TrimRight(strings.TrimRight(
					strings.Replace(
						json.Number(strings.TrimRight(
							strings.Replace(w1.Body.String(), " ", "", -1), "\n")).String(),
						"\"", "", -1), "0"), ".")
				_ = v
			case string:
				idStr = v
			}
			if idStr != "" {
				w2 := doDELETE(t, r, "/admin/users/"+idStr)
				t.Logf("DeleteUser: %d %s", w2.Code, w2.Body.String())
			}
		}
	}
}

// ── Register ─────────────────────────────────────────────────────────

func TestIntegration_RegisterBadRequest(t *testing.T) {
	r := gin.New()
	r.POST("/register", testHandler.Register)

	w := doPOST(t, r, "/register", `{}`)
	t.Logf("Register empty: %d %s", w.Code, w.Body.String())
	if w.Code == 200 || w.Code == 201 {
		t.Error("Register with empty body should not succeed")
	}
}

// ── ExportSalesCSV ───────────────────────────────────────────────────

func TestIntegration_ExportSalesCSV(t *testing.T) {
	r := withAuth()
	r.GET("/export-csv", testHandler.ExportSalesCSV)

	w := doGET(t, r, "/export-csv?period=7d&limit=5")
	t.Logf("ExportSalesCSV: %d, CT=%s, Size=%d", w.Code, w.Header().Get("Content-Type"), w.Body.Len())
	expectCode(t, "ExportSalesCSV", w, 200)
}

// ── HealthCheck (duplicate endpoint) ─────────────────────────────────

func TestIntegration_HealthCheck(t *testing.T) {
	r := gin.New()
	r.GET("/hc", testHandler.HealthCheck)

	w := doGET(t, r, "/hc")
	t.Logf("HealthCheck: %d %s", w.Code, w.Body.String())
	expectCode(t, "HealthCheck", w, 200)
}
