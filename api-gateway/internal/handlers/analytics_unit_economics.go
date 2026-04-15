package handlers

import (
	"fmt"
	"math"
	"strconv"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetUnitEconomicsFull(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "30d")
	catSlug := c.Query("category")
	mpSlug := c.Query("marketplace")
	sortBy := c.DefaultQuery("sort", "revenue")
	order := c.DefaultQuery("order", "desc")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if page < 1 { page = 1 }
	if limit < 1 || limit > 200 { limit = 50 }
	offset := (page - 1) * limit

	dateFrom, dateTo := h.parsePeriod(period)

	j := ` FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id`

	w, a := buildSalesWhere(dateFrom, dateTo, catSlug, mpSlug)

	allowed := map[string]string{
		"revenue": "revenue", "profit": "profit", "margin": "margin_pct",
		"roi": "roi", "quantity": "qty", "name": "p.name",
	}
	col, ok := allowed[sortBy]
	if !ok { col = "revenue" }
	if order != "asc" { order = "desc" }

	var total int
	cntQ := fmt.Sprintf("SELECT COUNT(DISTINCT p.id) %s %s AND s.quantity > 0", j, w)
	_ = h.db.QueryRow(ctx, cntQ, a...).Scan(&total)

	q := fmt.Sprintf(`SELECT p.id, p.sku, p.name, COALESCE(c.name,''),
		COALESCE(p.cost_price, 0),
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0) as revenue,
		COALESCE(SUM(s.net_profit), 0) as profit,
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0) as qty,
		COALESCE(SUM(s.commission), 0) as comm,
		COALESCE(SUM(s.logistics_cost), 0) as logi,
		COALESCE(SUM(s.storage_fee), 0) as stor,
		CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
			THEN SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END)
				/ SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END)
			ELSE 0 END as avg_price,
		CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END) > 0
			THEN SUM(s.net_profit)
				/ SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END) * 100
			ELSE 0 END as margin_pct,
		CASE WHEN COALESCE(p.cost_price,0) > 0 AND SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
			THEN (SUM(s.net_profit)) / (p.cost_price * SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END)) * 100
			ELSE 0 END as roi
		%s %s AND s.quantity > 0
		GROUP BY p.id, p.sku, p.name, c.name, p.cost_price
		ORDER BY %s %s NULLS LAST
		LIMIT %d OFFSET %d`, j, w, col, order, limit, offset)

	rows, err := h.db.Query(ctx, q, a...)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	var items []gin.H
	var sumMargin, sumROI float64
	var profitable, unprofitable int

	for rows.Next() {
		var id, qty int
		var sku, name, cat string
		var costPrice, revenue, profit, comm, logi, stor float64
		var avgPrice, marginPct, roi float64
		if rows.Scan(&id, &sku, &name, &cat, &costPrice,
			&revenue, &profit, &qty, &comm, &logi, &stor,
			&avgPrice, &marginPct, &roi) != nil {
			continue
		}
		unitComm := div(comm, float64(qty))
		unitLogi := div(logi, float64(qty))
		unitStor := div(stor, float64(qty))
		unitProfit := div(profit, float64(qty))

		items = append(items, gin.H{
			"product_id": id, "sku": sku, "name": name, "category": cat,
			"price": round2(avgPrice), "cost": round2(costPrice),
			"commission": round2(unitComm), "logistics": round2(unitLogi),
			"storage": round2(unitStor), "margin": round2(unitProfit),
			"margin_pct": round2(marginPct), "roi": round2(roi),
			"quantity": qty, "revenue": round2(revenue), "profit": round2(profit),
		})
		sumMargin += marginPct
		sumROI += roi
		if profit > 0 { profitable++ } else { unprofitable++ }
	}
	if items == nil { items = []gin.H{} }

	cnt := len(items)
	avgMargin := 0.0
	avgROI := 0.0
	if cnt > 0 {
		avgMargin = sumMargin / float64(cnt)
		avgROI = sumROI / float64(cnt)
	}

	totalPages := int(math.Ceil(float64(total) / float64(limit)))
	if totalPages < 1 { totalPages = 1 }

	c.JSON(200, gin.H{
		"period": period,
		"items": items,
		"summary": gin.H{
			"avg_margin": round2(avgMargin), "avg_roi": round2(avgROI),
			"profitable_count": profitable, "unprofitable_count": unprofitable,
			"total": total,
		},
		"page": page, "limit": limit, "total_pages": totalPages,
	})
}
