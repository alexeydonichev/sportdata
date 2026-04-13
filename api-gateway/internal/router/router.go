package router

import (
	"os"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"sportdata-api/internal/handlers"
	"sportdata-api/internal/middleware"
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

	rl := middleware.NewRateLimiter(30, 60)
	r.Use(rl.RateLimit())
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.CORS())

	h := handlers.New(db, redisClient)

	r.GET("/health", h.Health)
	r.POST("/api/v1/auth/login", h.Login)

	auth := r.Group("/api/v1")
	auth.Use(middleware.AuthRequired())
	{
		auth.GET("/auth/me", middleware.RoleRequired(4), h.GetMe)

		auth.GET("/dashboard", middleware.RoleRequired(4), h.GetDashboard)
		auth.GET("/dashboard/chart", middleware.RoleRequired(4), h.GetDashboardChart)
		auth.GET("/products", middleware.RoleRequired(4), h.GetProducts)
		auth.POST("/products/bulk-cost", middleware.RoleRequired(3), h.BulkUpdateCostPrice)
		auth.GET("/products/:id", middleware.RoleRequired(4), h.GetProductDetail)
		auth.PATCH("/products/:id", middleware.RoleRequired(3), h.UpdateProduct)
		auth.GET("/categories", middleware.RoleRequired(4), h.GetCategories)
		auth.GET("/marketplaces", middleware.RoleRequired(4), h.GetMarketplaces)
		auth.GET("/sales", middleware.RoleRequired(4), h.GetSales)
		auth.GET("/sales/export", middleware.RoleRequired(4), h.ExportSalesCSV)
		auth.GET("/export/sales", middleware.RoleRequired(4), h.ExportSales)
		auth.GET("/export/products", middleware.RoleRequired(4), h.ExportProducts)
		auth.GET("/export/analytics", middleware.RoleRequired(4), h.ExportAnalytics)
		auth.GET("/inventory", middleware.RoleRequired(4), h.GetInventory)
		auth.GET("/notifications", middleware.RoleRequired(4), h.GetNotifications)
		auth.GET("/profile", middleware.RoleRequired(4), h.GetProfile)

		auth.GET("/analytics/pnl", middleware.RoleRequired(4), h.GetPnL)
		auth.GET("/analytics/abc", middleware.RoleRequired(4), h.GetABC)
		auth.GET("/analytics/unit-economics", middleware.RoleRequired(4), h.GetUnitEconomics)
		auth.GET("/analytics/trending", middleware.RoleRequired(4), h.GetTrending)
		auth.GET("/analytics/categories", middleware.RoleRequired(4), h.GetCategoriesAnalytics)
		auth.GET("/analytics/brands", middleware.RoleRequired(4), h.GetBrandsAnalytics)
		auth.GET("/analytics/geography", middleware.RoleRequired(4), h.GetGeography)
		auth.GET("/analytics/warehouses", middleware.RoleRequired(4), h.GetWarehousesAnalytics)
		auth.GET("/analytics/finance", middleware.RoleRequired(4), h.GetFinance)
		auth.GET("/analytics/returns", middleware.RoleRequired(4), h.GetReturnsAnalytics)

		auth.GET("/projects", middleware.RoleRequired(4), h.GetProjects)

		auth.GET("/invites", middleware.RoleRequired(2), h.GetInvites)
		auth.POST("/invites", middleware.RoleRequired(2), h.CreateInvite)

		mgmt := auth.Group("")
		mgmt.Use(middleware.RoleRequired(2))
		{
			mgmt.GET("/sync/status", h.GetSyncStatus)
			mgmt.GET("/sync/credentials", h.GetSyncCredentials)
			mgmt.POST("/sync/credentials", h.SaveSyncCredential)
			mgmt.DELETE("/sync/credentials", h.DeleteSyncCredential)
			mgmt.GET("/sync/history", h.GetSyncHistory)
			mgmt.POST("/sync/trigger/:marketplace", h.TriggerSync)
		}

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

		sa := auth.Group("/_sa")
		sa.Use(middleware.SuperAdminOnly())
		{
			sa.GET("/audit", h.GetAuditLog)
			sa.GET("/system", h.GetSystemInfo)
			sa.GET("/users/all", h.GetAllUsersIncludingHidden)
		}

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
