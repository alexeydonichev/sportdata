package handlers

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetWarehousesAnalytics(c *gin.Context) {
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
		SELECT COALESCE(NULLIF(s.warehouse,''),'Не указан'),
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float8,
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int,
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.net_profit ELSE 0 END),0)::float8,
			COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int
		FROM sales s
		JOIN marketplaces mp ON mp.id=s.marketplace_id
		WHERE s.sale_date>=CURRENT_DATE-$1::int %s
		GROUP BY s.warehouse ORDER BY 2 DESC LIMIT 50
	`, mpF), params...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var warehouses []gin.H
	var totalRev float64
	for rows.Next() {
		var nm string
		var rev, profit float64
		var qty, ret int
		rows.Scan(&nm, &rev, &qty, &profit, &ret)
		totalRev += rev
		rr := 0.0
		if (qty + ret) > 0 {
			rr = float64(ret) / float64(qty+ret) * 100
		}
		warehouses = append(warehouses, gin.H{
			"warehouse": nm, "revenue": round2(rev), "quantity": qty,
			"profit": round2(profit), "returns": ret, "return_rate": round2(rr),
		})
	}

	for i, w := range warehouses {
		rev := w["revenue"].(float64)
		share := 0.0
		if totalRev > 0 {
			share = rev / totalRev * 100
		}
		warehouses[i]["share"] = round2(share)
	}
	if warehouses == nil {
		warehouses = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{
		"period":           period,
		"warehouses":       warehouses,
		"total_warehouses": len(warehouses),
		"total_revenue":    round2(totalRev),
	})
}
