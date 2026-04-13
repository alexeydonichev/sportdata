package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetReturnsAnalytics(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := parsePeriod(period)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	var totalOrders, totalReturns int
	var returnsAmount float64
	h.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(quantity),0), COALESCE(SUM(returns_qty),0), COALESCE(SUM(returns_amount),0)
		FROM sales WHERE sale_date >= $1 AND sale_date <= $2
	`, dateFrom, dateTo).Scan(&totalOrders, &totalReturns, &returnsAmount)

	returnRate := pct(float64(totalReturns), float64(totalOrders))

	rows, _ := h.db.Query(ctx, `
		SELECT p.name, COALESCE(SUM(s.returns_qty),0) as ret, COALESCE(SUM(s.quantity),0) as qty
		FROM sales s JOIN products p ON p.id = s.product_id
		WHERE s.sale_date >= $1 AND s.sale_date <= $2 AND s.returns_qty > 0
		GROUP BY p.name ORDER BY ret DESC LIMIT 20
	`, dateFrom, dateTo)
	defer rows.Close()

	type retProduct struct {
		Name       string  `json:"name"`
		Returns    int     `json:"returns"`
		Quantity   int     `json:"quantity"`
		ReturnRate float64 `json:"return_rate"`
	}
	var products []retProduct
	for rows.Next() {
		var rp retProduct
		rows.Scan(&rp.Name, &rp.Returns, &rp.Quantity)
		rp.ReturnRate = round2(pct(float64(rp.Returns), float64(rp.Quantity)))
		products = append(products, rp)
	}
	if products == nil {
		products = []retProduct{}
	}

	c.JSON(http.StatusOK, gin.H{
		"summary": gin.H{
			"total_returns":  totalReturns,
			"returns_amount": round2(returnsAmount),
			"return_rate":    round2(returnRate),
		},
		"top_returned_products": products,
		"period":                gin.H{"from": dateFrom, "to": dateTo},
	})
}
