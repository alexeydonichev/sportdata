package handlers

import (
	"github.com/gin-gonic/gin"
)

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
