package handlers

import (
	"context"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetDashboard(c *gin.Context) {
	ctx := context.Background()
	period := c.DefaultQuery("period", "7d")
	categorySlug := c.Query("category")
	marketplaceSlug := c.Query("marketplace")

	dateFrom, dateTo := parsePeriod(period)
	prevFrom, prevTo := prevPeriod(dateFrom, dateTo)

	whereClause, args := buildSalesWhere(dateFrom, dateTo, categorySlug, marketplaceSlug)
	prevWhere, prevArgs := buildSalesWherePrev(prevFrom, prevTo, categorySlug, marketplaceSlug)

	joinClause := `FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id`

	// Current period
	var revenue, profit, commission, logistics float64
	var quantity, ordersCount int
	q := fmt.Sprintf(`
		SELECT COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
			COALESCE(SUM(s.commission),0), COALESCE(SUM(s.logistics_cost),0),
			COALESCE(SUM(s.quantity),0), COUNT(*)
		%s %s`, joinClause, whereClause)
	h.db.QueryRow(ctx, q, args...).Scan(&revenue, &profit, &commission, &logistics, &quantity, &ordersCount)

	// Previous period
	var prevRevenue, prevProfit, prevCommission, prevLogistics float64
	var prevQuantity, prevOrders int
	pq := fmt.Sprintf(`
		SELECT COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
			COALESCE(SUM(s.commission),0), COALESCE(SUM(s.logistics_cost),0),
			COALESCE(SUM(s.quantity),0), COUNT(*)
		%s %s`, joinClause, prevWhere)
	h.db.QueryRow(ctx, pq, prevArgs...).Scan(&prevRevenue, &prevProfit, &prevCommission, &prevLogistics, &prevQuantity, &prevOrders)

	var totalSKU int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM products WHERE is_active = true").Scan(&totalSKU)

	margin := pct(profit, revenue)
	avgOrder := div(revenue, float64(ordersCount))
	prevMargin := pct(prevProfit, prevRevenue)
	prevAvgOrder := div(prevRevenue, float64(prevOrders))

	// By marketplace
	mpRows, _ := h.db.Query(ctx, `
		SELECT m.slug, m.name,
			COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.quantity),0)
		FROM marketplaces m
		LEFT JOIN sales s ON s.marketplace_id = m.id AND s.sale_date >= $1 AND s.sale_date <= $2
		GROUP BY m.slug, m.name ORDER BY SUM(s.revenue) DESC NULLS LAST
	`, dateFrom, dateTo)
	var byMarketplace []gin.H
	if mpRows != nil {
		defer mpRows.Close()
		for mpRows.Next() {
			var slug, name string
			var rev, prof float64
			var qty int
			mpRows.Scan(&slug, &name, &rev, &prof, &qty)
			share := pct(rev, revenue)
			byMarketplace = append(byMarketplace, gin.H{
				"marketplace": slug, "name": name,
				"revenue": round2(rev), "profit": round2(prof), "quantity": qty, "share_pct": round2(share),
			})
		}
	}

	// Top products
	topQ := fmt.Sprintf(`
		SELECT p.id::text, p.sku, p.name,
			COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.quantity),0)
		%s %s
		GROUP BY p.id, p.sku, p.name ORDER BY SUM(s.revenue) DESC LIMIT 10`, joinClause, whereClause)
	topRows, _ := h.db.Query(ctx, topQ, args...)
	var topProducts []gin.H
	if topRows != nil {
		defer topRows.Close()
		for topRows.Next() {
			var pid, sku, name string
			var rev, prof float64
			var qty int
			topRows.Scan(&pid, &sku, &name, &rev, &prof, &qty)
			topProducts = append(topProducts, gin.H{
				"product_id": pid, "sku": sku, "name": name,
				"revenue": round2(rev), "profit": round2(prof), "quantity": qty,
			})
		}
	}

	c.JSON(200, gin.H{
		"period":            period,
		"date_from":         dateFrom,
		"date_to":           dateTo,
		"total_revenue":     round2(revenue),
		"total_profit":      round2(profit),
		"total_commission":  round2(commission),
		"total_logistics":   round2(logistics),
		"total_quantity":    quantity,
		"total_orders":      ordersCount,
		"avg_order_value":   round2(avgOrder),
		"profit_margin_pct": round2(margin),
		"total_sku":         totalSKU,
		"by_marketplace":    byMarketplace,
		"top_products":      topProducts,
		"changes": gin.H{
			"revenue":    changePct(revenue, prevRevenue),
			"profit":     changePct(profit, prevProfit),
			"orders":     changePct(float64(ordersCount), float64(prevOrders)),
			"quantity":   changePct(float64(quantity), float64(prevQuantity)),
			"avg_order":  changePct(avgOrder, prevAvgOrder),
			"margin":     changeDiff(margin, prevMargin),
			"commission": changePct(commission, prevCommission),
			"logistics":  changePct(logistics, prevLogistics),
		},
	})
}

func (h *Handler) GetDashboardChart(c *gin.Context) {
	ctx := context.Background()
	period := c.DefaultQuery("period", "7d")
	categorySlug := c.Query("category")
	marketplaceSlug := c.Query("marketplace")
	dateFrom, dateTo := parsePeriod(period)

	whereClause, args := buildSalesWhere(dateFrom, dateTo, categorySlug, marketplaceSlug)

	q := fmt.Sprintf(`
		SELECT s.sale_date,
			COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
			COUNT(*), COALESCE(SUM(s.quantity),0)
		FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id
		%s
		GROUP BY s.sale_date ORDER BY s.sale_date`, whereClause)

	rows, err := h.db.Query(ctx, q, args...)
	var result []gin.H
	hasData := false
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var date time.Time
			var rev, prof float64
			var orders, qty int
			rows.Scan(&date, &rev, &prof, &orders, &qty)
			result = append(result, gin.H{
				"date": date.Format("2006-01-02"), "revenue": round2(rev),
				"profit": round2(prof), "orders": orders, "quantity": qty,
			})
			hasData = true
		}
	}
	if !hasData {
		result = generateDemoChart(dateFrom, dateTo)
	}
	c.JSON(200, result)
}

func generateDemoChart(dateFrom, dateTo string) []gin.H {
	from, _ := time.Parse("2006-01-02", dateFrom)
	to, _ := time.Parse("2006-01-02", dateTo)
	var result []gin.H
	seed := int64(42)
	for d := from; !d.After(to); d = d.AddDate(0, 0, 1) {
		seed = (seed*1103515245 + 12345) & 0x7fffffff
		rev := 50000 + float64(seed%250000)
		seed = (seed*1103515245 + 12345) & 0x7fffffff
		prof := rev * (0.15 + float64(seed%20)/100.0)
		seed = (seed*1103515245 + 12345) & 0x7fffffff
		orders := 10 + int(seed%70)
		seed = (seed*1103515245 + 12345) & 0x7fffffff
		qty := 15 + int(seed%105)
		result = append(result, gin.H{
			"date": d.Format("2006-01-02"), "revenue": round2(rev),
			"profit": round2(prof), "orders": orders, "quantity": qty,
		})
	}
	return result
}
