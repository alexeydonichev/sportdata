package handlers

import (
	"context"
	"fmt"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type Handler struct {
	db    *pgxpool.Pool
	redis *redis.Client
}

func New(db *pgxpool.Pool, redis *redis.Client) *Handler {
	return &Handler{db: db, redis: redis}
}

func (h *Handler) Health(c *gin.Context) {
	ctx := context.Background()
	dbOK := h.db.Ping(ctx) == nil
	redisOK := h.redis.Ping(ctx).Err() == nil
	status := "healthy"
	code := http.StatusOK
	if !dbOK || !redisOK {
		status = "degraded"
		code = http.StatusServiceUnavailable
	}
	c.JSON(code, gin.H{
		"status": status, "service": "yourfit-analytics", "version": "0.2.0",
		"postgres": dbOK, "redis": redisOK, "time": time.Now().Format(time.RFC3339),
	})
}

func (h *Handler) GetMarketplaces(c *gin.Context) {
	ctx := context.Background()
	rows, err := h.db.Query(ctx, "SELECT id, slug, name, is_active FROM marketplaces ORDER BY id")
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()
	var result []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		var isActive bool
		rows.Scan(&id, &slug, &name, &isActive)
		result = append(result, gin.H{"id": id, "slug": slug, "name": name, "is_active": isActive})
	}
	c.JSON(200, gin.H{"data": result, "count": len(result)})
}

func (h *Handler) GetCategories(c *gin.Context) {
	ctx := context.Background()
	rows, err := h.db.Query(ctx, `
		SELECT c.id, c.slug, c.name, c.parent_id,
			COUNT(p.id) as product_count,
			COALESCE(SUM(sub.revenue), 0) as revenue
		FROM categories c
		LEFT JOIN products p ON p.category_id = c.id AND p.is_active = true
		LEFT JOIN (
			SELECT s.product_id, SUM(s.revenue) as revenue
			FROM sales s WHERE s.sale_date >= NOW() - INTERVAL '90 days'
			GROUP BY s.product_id
		) sub ON sub.product_id = p.id
		GROUP BY c.id, c.slug, c.name, c.parent_id
		ORDER BY c.sort_order, c.name
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()
	var result []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		var parentID *int
		var productCount int
		var revenue float64
		rows.Scan(&id, &slug, &name, &parentID, &productCount, &revenue)
		item := gin.H{"slug": slug, "name": name, "product_count": productCount, "revenue": round2(revenue)}
		if parentID != nil {
			item["parent_id"] = *parentID
		}
		result = append(result, item)
	}
	c.JSON(200, result)
}

// ==================== УТИЛИТЫ ====================

func parsePeriod(period string) (string, string) {
	now := time.Now()
	dateTo := now.Format("2006-01-02")
	switch period {
	case "1d", "today":
		return now.Format("2006-01-02"), dateTo
	case "3d":
		return now.AddDate(0, 0, -3).Format("2006-01-02"), dateTo
	case "7d":
		return now.AddDate(0, 0, -7).Format("2006-01-02"), dateTo
	case "14d":
		return now.AddDate(0, 0, -14).Format("2006-01-02"), dateTo
	case "30d":
		return now.AddDate(0, -1, 0).Format("2006-01-02"), dateTo
	case "90d":
		return now.AddDate(0, -3, 0).Format("2006-01-02"), dateTo
	case "180d":
		return now.AddDate(0, -6, 0).Format("2006-01-02"), dateTo
	case "365d":
		return now.AddDate(-1, 0, 0).Format("2006-01-02"), dateTo
	case "all":
		return "2020-01-01", dateTo
	default:
		return now.AddDate(0, 0, -7).Format("2006-01-02"), dateTo
	}
}

func prevPeriod(dateFrom, dateTo string) (string, string) {
	from, _ := time.Parse("2006-01-02", dateFrom)
	to, _ := time.Parse("2006-01-02", dateTo)
	duration := to.Sub(from)
	prevTo := from.AddDate(0, 0, -1)
	prevFrom := prevTo.Add(-duration)
	return prevFrom.Format("2006-01-02"), prevTo.Format("2006-01-02")
}

func round2(f float64) float64 {
	return math.Round(f*100) / 100
}

func pct(part, total float64) float64 {
	if total == 0 {
		return 0
	}
	return part / total * 100
}

func div(a, b float64) float64 {
	if b == 0 {
		return 0
	}
	return a / b
}

func changePct(current, previous float64) *float64 {
	if previous == 0 {
		if current == 0 {
			return nil
		}
		v := 100.0
		return &v
	}
	v := round2((current - previous) / previous * 100)
	return &v
}

func changeDiff(current, previous float64) *float64 {
	v := round2(current - previous)
	return &v
}

func buildSalesWhere(dateFrom, dateTo, categorySlug, marketplaceSlug string) (string, []any) {
	conditions := []string{"s.sale_date >= $1", "s.sale_date <= $2"}
	args := []any{dateFrom, dateTo}
	argN := 3
	if categorySlug != "" && categorySlug != "all" {
		conditions = append(conditions, fmt.Sprintf("c.slug = $%d", argN))
		args = append(args, categorySlug)
		argN++
	}
	if marketplaceSlug != "" && marketplaceSlug != "all" {
		conditions = append(conditions, fmt.Sprintf("m.slug = $%d", argN))
		args = append(args, marketplaceSlug)
		argN++
	}
	return "WHERE " + strings.Join(conditions, " AND "), args
}

func buildSalesWherePrev(prevFrom, prevTo, categorySlug, marketplaceSlug string) (string, []any) {
	return buildSalesWhere(prevFrom, prevTo, categorySlug, marketplaceSlug)
}
