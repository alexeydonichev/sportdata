package router

import (
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"sportdata/api-gateway/internal/cache"
	"sportdata/api-gateway/internal/handlers"
	"sportdata/api-gateway/internal/middleware"
)

func Setup(db *pgxpool.Pool, redisClient *redis.Client) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(gin.Logger())

	proxies := os.Getenv("TRUSTED_PROXIES")
	if proxies == "" {
		r.SetTrustedProxies(nil)
	}

	rl := middleware.NewRateLimiter(120, 60)
	r.Use(rl.RateLimit())
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.CORS())

	h := handlers.New(db, redisClient)

	// Cache layers
	c30s := cache.CacheMiddleware(redisClient, 30*time.Second)
	c60s := cache.CacheMiddleware(redisClient, 60*time.Second)
	c5m := cache.CacheMiddleware(redisClient, 5*time.Minute)

	// ── Public (no auth) ────────────────────────────────────
	r.GET("/health", h.Health)
	r.GET("/api/v1/health", h.Health)
	r.POST("/api/v1/auth/login", h.Login)
	r.POST("/api/v1/auth/register", h.Register)

	// ── Authenticated ───────────────────────────────────────
	auth := r.Group("/api/v1")
	auth.Use(middleware.AuthRequired())
	{
		// --- auth / profile (no cache — user-specific mutable) ---
		auth.GET("/auth/me", middleware.RoleRequired(4), h.GetMe)
		auth.GET("/auth/profile", middleware.RoleRequired(4), h.GetProfile)
		auth.PUT("/auth/avatar", middleware.RoleRequired(4), h.UploadAvatar)
		auth.PUT("/auth/password", middleware.RoleRequired(4), h.ChangePassword)

		// --- dashboard (cached 30s) ---
		auth.GET("/dashboard", c30s, middleware.RoleRequired(4), h.GetDashboard)
		auth.GET("/dashboard/chart", c30s, middleware.RoleRequired(4), h.GetDashboardChart)

		// --- products (cached 30s) ---
		auth.GET("/products", c30s, middleware.RoleRequired(4), h.GetProducts)
		auth.POST("/products/bulk-cost", middleware.RoleRequired(3), h.BulkUpdateCostPrice)
		auth.GET("/products/categories", c5m, middleware.RoleRequired(4), h.GetCategories)
		auth.GET("/products/:id", c30s, middleware.RoleRequired(4), h.GetProductDetail)
		auth.PATCH("/products/:id", middleware.RoleRequired(3), h.UpdateProduct)

		// --- references (cached 5m) ---
		auth.GET("/marketplaces", c5m, middleware.RoleRequired(4), h.GetMarketplaces)

		// --- sales (cached 30s) ---
		auth.GET("/sales", c30s, middleware.RoleRequired(4), h.GetSales)

		// --- export (no cache — file downloads) ---
		auth.GET("/export/sales", middleware.RoleRequired(4), h.ExportSales)
		auth.GET("/export/products", middleware.RoleRequired(4), h.ExportProducts)
		auth.GET("/export/analytics", middleware.RoleRequired(4), h.ExportAnalytics)

		// --- inventory (cached 60s) ---
		auth.GET("/inventory", c60s, middleware.RoleRequired(4), h.GetInventory)

		// --- notifications (cached 60s) ---
		auth.GET("/notifications", c60s, middleware.RoleRequired(4), h.GetNotifications)

		// --- analytics (cached 60s) ---
		auth.GET("/analytics/pnl", c60s, middleware.RoleRequired(4), h.GetPnL)
		auth.GET("/analytics/abc", c60s, middleware.RoleRequired(4), h.GetABC)
		auth.GET("/analytics/unit-economics", c60s, middleware.RoleRequired(4), h.GetUnitEconomics)
		auth.GET("/analytics/trending", c60s, middleware.RoleRequired(4), h.GetTrending)
		auth.GET("/analytics/categories", c60s, middleware.RoleRequired(4), h.GetCategoriesAnalytics)
		auth.GET("/analytics/brands", c60s, middleware.RoleRequired(4), h.GetBrandsAnalytics)
		auth.GET("/analytics/geography", c60s, middleware.RoleRequired(4), h.GetGeography)
		auth.GET("/analytics/warehouses", c60s, middleware.RoleRequired(4), h.GetWarehousesAnalytics)
		auth.GET("/analytics/finance", c60s, middleware.RoleRequired(4), h.GetFinance)
		auth.GET("/analytics/returns", c60s, middleware.RoleRequired(4), h.GetReturnsAnalytics)
		auth.GET("/analytics/rnp", c60s, middleware.RoleRequired(4), h.GetAnalyticsRNP)

		// --- projects (cached 60s) ---
		auth.GET("/projects", c60s, middleware.RoleRequired(4), h.GetProjects)

		// --- invites (no cache — mutable) ---
		auth.GET("/invites", middleware.RoleRequired(2), h.GetInvites)
		auth.POST("/invites", middleware.RoleRequired(2), h.CreateInvite)

		// --- supplier (proxy to WB/Ozon) ---
		auth.GET("/supplier/sales", middleware.RoleRequired(4), h.GetSupplierSales)
		auth.GET("/supplier/stocks", middleware.RoleRequired(4), h.GetSupplierStocks)

		// ── Management (role 2+) ────────────────────────────
		mgmt := auth.Group("")
		mgmt.Use(middleware.RoleRequired(2))
		{
			mgmt.GET("/sync/status", h.GetSyncStatus)
			mgmt.GET("/sync/credentials", h.GetSyncCredentials)
			mgmt.POST("/sync/credentials", h.SaveSyncCredential)
			mgmt.DELETE("/sync/credentials", h.DeleteSyncCredential)
			mgmt.GET("/sync/history", h.GetSyncHistory)
			mgmt.POST("/sync/trigger/:marketplace", h.TriggerSync)
			mgmt.POST("/sync/trigger", h.TriggerSync)
			mgmt.POST("/sync/cron", h.CronSync)
		}

		// ── Owners (role 1) ─────────────────────────────────
		owners := auth.Group("")
		owners.Use(middleware.RoleRequired(1))
		{
			owners.GET("/roles", h.GetRoles)
			owners.GET("/departments", h.GetDepartments)
			owners.GET("/users", h.GetUsers)
			owners.POST("/users", h.CreateUser)
			owners.PATCH("/users/:id", h.UpdateUser)
			owners.DELETE("/users/:id", h.DeleteUser)
		}

		// ── Super Admin ─────────────────────────────────────
		sa := auth.Group("/_sa")
		sa.Use(middleware.SuperAdminOnly())
		{
			sa.GET("/audit", h.GetAuditLog)
			sa.GET("/system", h.GetSystemInfo)
			sa.GET("/users/all", h.GetAllUsersIncludingHidden)
		}

		// ── RNP ─────────────────────────────────────────────
		rnp := auth.Group("/rnp")
		rnp.Use(middleware.RoleRequired(4))
		{
			rnp.GET("/managers", h.GetManagers)
			rnp.GET("/checklist-templates", h.GetChecklistTemplates)
			rnp.GET("/templates", h.GetRNPTemplates)
			rnp.POST("/templates", middleware.RoleRequired(3), h.CreateRNPTemplate)
			rnp.GET("/templates/:id", h.GetRNPItems)
			rnp.POST("/templates/:id/items", h.CreateRNPItem)
			rnp.PATCH("/items/:itemId", h.UpdateRNPItem)
			rnp.DELETE("/items/:itemId", h.DeleteRNPItem)
			rnp.GET("/items/:itemId/daily", h.GetRNPDailyStats)
			rnp.POST("/items/:itemId/daily", h.SaveRNPDailyStat)
			rnp.GET("/items/:itemId/checklist", h.GetRNPChecklist)
			rnp.POST("/items/:itemId/checklist/init", h.InitRNPChecklist)
			rnp.PATCH("/checklist/:checklistId", h.UpdateRNPChecklistItem)
		}
	}

	return r
}
