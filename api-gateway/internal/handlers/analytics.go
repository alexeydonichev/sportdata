package handlers

import (
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetAnalytics(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "30d")
	catSlug := c.Query("category")
	mpSlug := c.Query("marketplace")
	dateFrom, dateTo := h.parsePeriod(period)

	w, a := buildSalesWhere(dateFrom, dateTo, catSlug, mpSlug)

	j := ` FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id`

	// Revenue by category
	catRows, _ := h.db.Query(ctx, fmt.Sprintf(`SELECT c.slug, c.name,
		COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
		COALESCE(SUM(s.quantity),0) %s %s
		GROUP BY c.slug, c.name ORDER BY SUM(s.revenue) DESC NULLS LAST`, j, w), a...)
	var byCat []gin.H
	var totalRev float64
	if catRows != nil {
		defer catRows.Close()
		type catRow struct{ slug, name string; rev, prof float64; qty int }
		var tmp []catRow
		for catRows.Next() {
			var r catRow
			if catRows.Scan(&r.slug, &r.name, &r.rev, &r.prof, &r.qty) == nil {
				tmp = append(tmp, r)
				totalRev += r.rev
			}
		}
		for _, r := range tmp {
			byCat = append(byCat, gin.H{
				"category": r.slug, "name": r.name,
				"revenue": round2(r.rev), "profit": round2(r.prof),
				"quantity": r.qty, "share_pct": round2(pct(r.rev, totalRev)),
			})
		}
	}
	if byCat == nil { byCat = []gin.H{} }

	// Revenue by marketplace
	mpRows, _ := h.db.Query(ctx, fmt.Sprintf(`SELECT m.slug, m.name,
		COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
		COALESCE(SUM(s.quantity),0) %s %s
		GROUP BY m.slug, m.name ORDER BY SUM(s.revenue) DESC NULLS LAST`, j, w), a...)
	var byMP []gin.H
	if mpRows != nil {
		defer mpRows.Close()
		for mpRows.Next() {
			var sl, nm string
			var r, p float64
			var q int
			if mpRows.Scan(&sl, &nm, &r, &p, &q) == nil {
				byMP = append(byMP, gin.H{
					"marketplace": sl, "name": nm,
					"revenue": round2(r), "profit": round2(p),
					"quantity": q, "share_pct": round2(pct(r, totalRev)),
				})
			}
		}
	}
	if byMP == nil { byMP = []gin.H{} }

	// Daily trend
	trendRows, _ := h.db.Query(ctx, fmt.Sprintf(`SELECT s.sale_date,
		COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
		COALESCE(SUM(s.commission),0), COALESCE(SUM(s.logistics_cost),0),
		COUNT(*), COALESCE(SUM(s.quantity),0)
		%s %s GROUP BY s.sale_date ORDER BY s.sale_date`, j, w), a...)
	var trend []gin.H
	if trendRows != nil {
		defer trendRows.Close()
		for trendRows.Next() {
			var d time.Time
			var r, p, cm, lg float64
			var o, q int
			if trendRows.Scan(&d, &r, &p, &cm, &lg, &o, &q) == nil {
				trend = append(trend, gin.H{
					"date": d.Format("2006-01-02"),
					"revenue": round2(r), "profit": round2(p),
					"commission": round2(cm), "logistics": round2(lg),
					"orders": o, "quantity": q,
					"margin_pct": round2(pct(p, r)),
				})
			}
		}
	}
	if trend == nil { trend = []gin.H{} }

	// Cost breakdown
	var totRev, totProf, totComm, totLogi, totCost float64
	bq := fmt.Sprintf(`SELECT COALESCE(SUM(s.revenue),0),
		COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.commission),0),
		COALESCE(SUM(s.logistics_cost),0), COALESCE(SUM(p.cost_price * s.quantity),0)
		%s %s`, j, w)
	h.db.QueryRow(ctx, bq, a...).Scan(&totRev, &totProf, &totComm, &totLogi, &totCost)

	costs := gin.H{
		"total_revenue": round2(totRev),
		"cost_price": round2(totCost), "cost_price_pct": round2(pct(totCost, totRev)),
		"commission": round2(totComm), "commission_pct": round2(pct(totComm, totRev)),
		"logistics": round2(totLogi), "logistics_pct": round2(pct(totLogi, totRev)),
		"profit": round2(totProf), "profit_pct": round2(pct(totProf, totRev)),
	}

	c.JSON(200, gin.H{
		"period": period, "date_from": dateFrom, "date_to": dateTo,
		"by_category": byCat, "by_marketplace": byMP,
		"daily_trend": trend, "cost_breakdown": costs,
	})
}

func (h *Handler) GetAnalyticsABC(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := h.parsePeriod(period)

	rows, err := h.db.Query(ctx, `SELECT p.id, p.sku, p.name,
		COALESCE(SUM(s.revenue),0) as rev,
		COALESCE(SUM(s.net_profit),0) as prof,
		COALESCE(SUM(s.quantity),0) as qty
		FROM sales s
		JOIN products p ON p.id = s.product_id
		WHERE s.sale_date >= $1 AND s.sale_date <= $2
		
		GROUP BY p.id, p.sku, p.name
		ORDER BY rev DESC`, dateFrom, dateTo)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	type item struct {
		ID int; SKU, Name string; Rev, Prof float64; Qty int
	}
	var items []item
	var totalRev2 float64
	for rows.Next() {
		var it item
		if rows.Scan(&it.ID, &it.SKU, &it.Name, &it.Rev, &it.Prof, &it.Qty) == nil {
			items = append(items, it)
			totalRev2 += it.Rev
		}
	}

	var result []gin.H
	cumPct := 0.0
	for _, it := range items {
		sh := pct(it.Rev, totalRev2)
		cumPct += sh
		cat := "C"
		if cumPct <= 80 { cat = "A" } else if cumPct <= 95 { cat = "B" }
		result = append(result, gin.H{
			"product_id": it.ID, "sku": it.SKU, "name": it.Name,
			"revenue": round2(it.Rev), "profit": round2(it.Prof),
			"quantity": it.Qty, "share_pct": round2(sh),
			"cumulative_pct": round2(cumPct), "abc_category": cat,
		})
	}
	if result == nil { result = []gin.H{} }

	aCount, bCount, cCount := 0, 0, 0
	for _, r := range result {
		switch r["abc_category"] {
		case "A": aCount++
		case "B": bCount++
		case "C": cCount++
		}
	}

	c.JSON(200, gin.H{
		"period": period, "items": result,
		"summary": gin.H{"a_count": aCount, "b_count": bCount, "c_count": cCount, "total": len(result)},
	})
}
