package handlers

import (
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetDashboard(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "7d")
	catSlug := c.Query("category")
	mpSlug := c.Query("marketplace")

	dateFrom, dateTo := h.parsePeriod(period)
	prevFrom, prevTo := prevPeriod(dateFrom, dateTo)

	w, a := buildSalesWhere(dateFrom, dateTo, catSlug, mpSlug)
	pw, pa := buildSalesWherePrev(prevFrom, prevTo, catSlug, mpSlug)

	j := ` FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id`

	var rev, prof, comm, logi float64
	var qty, cnt int
	q := fmt.Sprintf(`SELECT COALESCE(SUM(s.revenue),0),
		COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.commission),0),
		COALESCE(SUM(s.logistics_cost),0), COALESCE(SUM(s.quantity),0),
		COUNT(*) %s %s`, j, w)
	if err := h.db.QueryRow(ctx, q, a...).Scan(
		&rev, &prof, &comm, &logi, &qty, &cnt); err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}

	var prevRev, prevProf, prevComm, prevLogi float64
	var prevQty, prevCnt int
	pq := fmt.Sprintf(`SELECT COALESCE(SUM(s.revenue),0),
		COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.commission),0),
		COALESCE(SUM(s.logistics_cost),0), COALESCE(SUM(s.quantity),0),
		COUNT(*) %s %s`, j, pw)
	_ = h.db.QueryRow(ctx, pq, pa...).Scan(
		&prevRev, &prevProf, &prevComm, &prevLogi, &prevQty, &prevCnt)

	var totalSKU int
	_ = h.db.QueryRow(ctx, "SELECT COUNT(*) FROM products WHERE is_active=true").Scan(&totalSKU)

	margin := pct(prof, rev)
	avgOrd := div(rev, float64(cnt))
	prevMargin := pct(prevProf, prevRev)
	prevAvg := div(prevRev, float64(prevCnt))

	mpRows, _ := h.db.Query(ctx, fmt.Sprintf(`SELECT m.slug, m.name,
		COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
		COALESCE(SUM(s.quantity),0) %s %s
		GROUP BY m.slug, m.name
		ORDER BY SUM(s.revenue) DESC NULLS LAST`, j, w), a...)
	var byMP []gin.H
	if mpRows != nil {
		defer mpRows.Close()
		for mpRows.Next() {
			var sl, nm string
			var r, p float64
			var q2 int
			if mpRows.Scan(&sl, &nm, &r, &p, &q2) == nil {
				byMP = append(byMP, gin.H{
					"marketplace": sl, "name": nm,
					"revenue": round2(r), "profit": round2(p),
					"quantity": q2, "share_pct": round2(pct(r, rev)),
				})
			}
		}
	}
	if byMP == nil {
		byMP = []gin.H{}
	}

	topRows, _ := h.db.Query(ctx, fmt.Sprintf(`SELECT p.id::text,
		p.sku, p.name, COALESCE(SUM(s.revenue),0),
		COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.quantity),0)
		%s %s GROUP BY p.id, p.sku, p.name
		ORDER BY SUM(s.revenue) DESC LIMIT 10`, j, w), a...)
	var topP []gin.H
	if topRows != nil {
		defer topRows.Close()
		for topRows.Next() {
			var id, sku, nm string
			var r, p float64
			var q2 int
			if topRows.Scan(&id, &sku, &nm, &r, &p, &q2) == nil {
				topP = append(topP, gin.H{
					"product_id": id, "sku": sku, "name": nm,
					"revenue": round2(r), "profit": round2(p), "quantity": q2,
				})
			}
		}
	}
	if topP == nil {
		topP = []gin.H{}
	}

	c.JSON(200, gin.H{
		"period": period, "date_from": dateFrom, "date_to": dateTo,
		"total_revenue": round2(rev), "total_profit": round2(prof),
		"total_commission": round2(comm), "total_logistics": round2(logi),
		"total_quantity": qty, "total_orders": cnt,
		"avg_order_value": round2(avgOrd), "profit_margin_pct": round2(margin),
		"total_sku": totalSKU,
		"by_marketplace": byMP, "top_products": topP,
		"changes": gin.H{
			"revenue":   changePct(rev, prevRev),
			"profit":    changePct(prof, prevProf),
			"orders":    changePct(float64(cnt), float64(prevCnt)),
			"quantity":  changePct(float64(qty), float64(prevQty)),
			"avg_order": changePct(avgOrd, prevAvg),
			"margin":    changeDiff(margin, prevMargin),
			"commission": changePct(comm, prevComm),
			"logistics": changePct(logi, prevLogi),
		},
	})
}

func (h *Handler) GetDashboardChart(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "7d")
	catSlug := c.Query("category")
	mpSlug := c.Query("marketplace")
	dateFrom, dateTo := h.parsePeriod(period)
	w, a := buildSalesWhere(dateFrom, dateTo, catSlug, mpSlug)

	q := fmt.Sprintf(`SELECT s.sale_date, COALESCE(SUM(s.revenue),0),
		COALESCE(SUM(s.net_profit),0), COUNT(*),
		COALESCE(SUM(s.quantity),0)
		FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id
		%s GROUP BY s.sale_date ORDER BY s.sale_date`, w)

	rows, err := h.db.Query(ctx, q, a...)
	var result []gin.H
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var d time.Time
			var r, p float64
			var o, q2 int
			if rows.Scan(&d, &r, &p, &o, &q2) == nil {
				result = append(result, gin.H{
					"date": d.Format("2006-01-02"),
					"revenue": round2(r), "profit": round2(p),
					"orders": o, "quantity": q2,
				})
			}
		}
	}
	if result == nil {
		result = []gin.H{}
	}
	c.JSON(200, result)
}
