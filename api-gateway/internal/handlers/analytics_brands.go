package handlers

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetBrandsAnalytics(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	days := parseDays(period)
	marketplace := c.Query("marketplace")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	params := []interface{}{days}
	mpF := ""
	if marketplace != "" && marketplace != "all" {
		params = append(params, marketplace)
		mpF = fmt.Sprintf("AND mp.slug=$%d", len(params))
	}

	rows, err := h.db.Query(ctx, fmt.Sprintf(`
		SELECT COALESCE(NULLIF(p.brand,''),'Без бренда'),
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float8,
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int,
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.net_profit ELSE 0 END),0)::float8,
			COUNT(DISTINCT CASE WHEN s.quantity>0 THEN s.product_id END)::int,
			COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int
		FROM sales s
		JOIN marketplaces mp ON mp.id=s.marketplace_id
		JOIN products p ON p.id=s.product_id
		WHERE s.sale_date>=CURRENT_DATE-$1::int %s
		GROUP BY p.brand ORDER BY 2 DESC LIMIT 50
	`, mpF), params...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var brands []gin.H
	var totalRev float64
	for rows.Next() {
		var nm string
		var rev, profit float64
		var qty, products, ret int
		_ = rows.Scan(&nm, &rev, &qty, &profit, &products, &ret)
		totalRev += rev
		margin := 0.0
		if rev > 0 {
			margin = profit / rev * 100
		}
		rr := 0.0
		if (qty + ret) > 0 {
			rr = float64(ret) / float64(qty+ret) * 100
		}
		brands = append(brands, gin.H{
			"name": nm, "revenue": round2(rev), "quantity": qty,
			"profit": round2(profit), "margin": round2(margin),
			"products": products, "returns": ret, "return_rate": round2(rr),
		})
	}

	for i, b := range brands {
		rev := b["revenue"].(float64)
		share := 0.0
		if totalRev > 0 {
			share = rev / totalRev * 100
		}
		brands[i]["share"] = round2(share)
	}
	if brands == nil {
		brands = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{
		"period":       period,
		"brands":       brands,
		"total_brands": len(brands),
		"total_revenue": round2(totalRev),
	})
}
