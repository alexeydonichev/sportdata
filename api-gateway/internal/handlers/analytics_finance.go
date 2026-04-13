package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetFinance(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := parsePeriod(period)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	var revenue, cost, profit, logistics, storage, commission, ads float64
	h.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(revenue),0), COALESCE(SUM(cost),0), COALESCE(SUM(profit),0),
			COALESCE(SUM(logistics_cost),0), COALESCE(SUM(storage_cost),0),
			COALESCE(SUM(commission),0), COALESCE(SUM(advertising_cost),0)
		FROM sales WHERE sale_date >= $1 AND sale_date <= $2
	`, dateFrom, dateTo).Scan(&revenue, &cost, &profit, &logistics, &storage, &commission, &ads)

	totalExpenses := cost + logistics + storage + commission + ads

	c.JSON(http.StatusOK, gin.H{
		"summary": gin.H{
			"revenue":        round2(revenue),
			"total_expenses": round2(totalExpenses),
			"profit":         round2(profit),
			"margin":         round2(pct(profit, revenue)),
		},
		"expenses_breakdown": gin.H{
			"cost_of_goods": round2(cost),
			"logistics":     round2(logistics),
			"storage":       round2(storage),
			"commission":    round2(commission),
			"advertising":   round2(ads),
		},
		"period": gin.H{"from": dateFrom, "to": dateTo},
	})
}
