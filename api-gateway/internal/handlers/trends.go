package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetTrends(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := parsePeriod(period)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	// Revenue trend по дням
	rows, _ := h.db.Query(ctx, `
		SELECT sale_date::text,
			COALESCE(SUM(revenue),0),
			COALESCE(SUM(profit),0),
			COALESCE(SUM(quantity),0)
		FROM sales
		WHERE sale_date >= $1 AND sale_date <= $2
		GROUP BY sale_date
		ORDER BY sale_date
	`, dateFrom, dateTo)
	defer rows.Close()

	type dayTrend struct {
		Date    string  `json:"date"`
		Revenue float64 `json:"revenue"`
		Profit  float64 `json:"profit"`
		Orders  int     `json:"orders"`
	}
	var daily []dayTrend
	for rows.Next() {
		var d dayTrend
		rows.Scan(&d.Date, &d.Revenue, &d.Profit, &d.Orders)
		daily = append(daily, d)
	}
	if daily == nil {
		daily = []dayTrend{}
	}

	// По категориям
	catRows, _ := h.db.Query(ctx, `
		SELECT COALESCE(c.name, 'Без категории'),
			COALESCE(SUM(s.revenue),0),
			COALESCE(SUM(s.profit),0),
			COALESCE(SUM(s.quantity),0)
		FROM sales s
		LEFT JOIN categories c ON c.id = s.category_id
		WHERE s.sale_date >= $1 AND s.sale_date <= $2
		GROUP BY c.name
		ORDER BY SUM(s.revenue) DESC
	`, dateFrom, dateTo)
	defer catRows.Close()

	type catTrend struct {
		Category string  `json:"category"`
		Revenue  float64 `json:"revenue"`
		Profit   float64 `json:"profit"`
		Orders   int     `json:"orders"`
	}
	var categories []catTrend
	for catRows.Next() {
		var ct catTrend
		catRows.Scan(&ct.Category, &ct.Revenue, &ct.Profit, &ct.Orders)
		categories = append(categories, ct)
	}
	if categories == nil {
		categories = []catTrend{}
	}

	// По маркетплейсам
	mpRows, _ := h.db.Query(ctx, `
		SELECT COALESCE(m.name, 'Неизвестно'),
			COALESCE(SUM(s.revenue),0),
			COALESCE(SUM(s.profit),0),
			COALESCE(SUM(s.quantity),0)
		FROM sales s
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id
		WHERE s.sale_date >= $1 AND s.sale_date <= $2
		GROUP BY m.name
		ORDER BY SUM(s.revenue) DESC
	`, dateFrom, dateTo)
	defer mpRows.Close()

	type mpTrend struct {
		Marketplace string  `json:"marketplace"`
		Revenue     float64 `json:"revenue"`
		Profit      float64 `json:"profit"`
		Orders      int     `json:"orders"`
	}
	var marketplaces []mpTrend
	for mpRows.Next() {
		var mt mpTrend
		mpRows.Scan(&mt.Marketplace, &mt.Revenue, &mt.Profit, &mt.Orders)
		marketplaces = append(marketplaces, mt)
	}
	if marketplaces == nil {
		marketplaces = []mpTrend{}
	}

	c.JSON(http.StatusOK, gin.H{
		"daily":        daily,
		"categories":   categories,
		"marketplaces": marketplaces,
		"period":       gin.H{"from": dateFrom, "to": dateTo},
	})
}
