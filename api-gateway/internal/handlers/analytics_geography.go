package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetGeography(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := parsePeriod(period)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	rows, _ := h.db.Query(ctx, `
		SELECT COALESCE(s.region, 'Неизвестно'),
			COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.quantity),0), COALESCE(SUM(s.profit),0)
		FROM sales s
		WHERE s.sale_date >= $1 AND s.sale_date <= $2
		GROUP BY s.region ORDER BY SUM(s.revenue) DESC
	`, dateFrom, dateTo)
	defer rows.Close()

	type regionData struct {
		Region  string  `json:"region"`
		Revenue float64 `json:"revenue"`
		Orders  int     `json:"orders"`
		Profit  float64 `json:"profit"`
	}
	var data []regionData
	for rows.Next() {
		var r regionData
		rows.Scan(&r.Region, &r.Revenue, &r.Orders, &r.Profit)
		data = append(data, r)
	}
	if data == nil {
		data = []regionData{}
	}

	c.JSON(http.StatusOK, gin.H{"data": data, "period": gin.H{"from": dateFrom, "to": dateTo}})
}
