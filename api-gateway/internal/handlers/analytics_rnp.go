package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// GetAnalyticsRNP — сводная аналитика по РНП (список items с метриками)
func (h *Handler) GetAnalyticsRNP(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := h.parsePeriod(period)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 200 {
		limit = 50
	}
	offset := (page - 1) * limit

	type rnpRow struct {
		ID           string  `json:"id"`
		TemplateName string  `json:"template_name"`
		ProductName  string  `json:"product_name"`
		SKU          string  `json:"sku"`
		Target       float64 `json:"target"`
		Actual       float64 `json:"actual"`
		Progress     float64 `json:"progress"`
		Status       string  `json:"status"`
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT
			ri.id,
			rt.year || '-' || LPAD(rt.month::text, 2, '0') AS template_name,
			COALESCE(ri.name, '')  AS product_name,
			COALESCE(ri.sku, '')   AS sku,
			COALESCE(ri.plan_orders_qty, 0) AS target,
			COALESCE(SUM(rd.fact_orders_qty), 0) AS actual,
			CASE WHEN COALESCE(ri.plan_orders_qty, 0) > 0
				THEN ROUND(COALESCE(SUM(rd.fact_orders_qty), 0)::numeric / ri.plan_orders_qty * 100, 1)
				ELSE 0 END AS progress,
			CASE
				WHEN COALESCE(SUM(rd.fact_orders_qty), 0) >= COALESCE(ri.plan_orders_qty, 0) THEN 'done'
				WHEN COALESCE(SUM(rd.fact_orders_qty), 0) > 0 THEN 'in_progress'
				ELSE 'not_started'
			END AS status
		FROM rnp_items ri
		JOIN rnp_templates rt ON rt.id = ri.template_id
		LEFT JOIN rnp_daily_facts rd ON rd.item_id = ri.id
			AND rd.fact_date BETWEEN $1 AND $2
		GROUP BY ri.id, rt.year, rt.month, ri.name, ri.sku, ri.plan_orders_qty
		ORDER BY progress DESC
		LIMIT $3 OFFSET $4
	`, dateFrom, dateTo, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	items := make([]rnpRow, 0)
	for rows.Next() {
		var r rnpRow
		if err := rows.Scan(&r.ID, &r.TemplateName, &r.ProductName, &r.SKU,
			&r.Target, &r.Actual, &r.Progress, &r.Status); err != nil {
			continue
		}
		items = append(items, r)
	}

	var total int
	_ = h.db.QueryRow(c.Request.Context(), `SELECT COUNT(*) FROM rnp_items`).Scan(&total)

	c.JSON(http.StatusOK, gin.H{
		"items": items,
		"total": total,
		"page":  page,
		"limit": limit,
	})
}
