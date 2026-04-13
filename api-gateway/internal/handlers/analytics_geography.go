package handlers

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetGeography(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	days := parseDays(period)
	category := c.Query("category")
	marketplace := c.Query("marketplace")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	params := []interface{}{days}
	catF, mpF := "", ""
	idx := 1
	if category != "" && category != "all" {
		idx++
		params = append(params, category)
		catF = fmt.Sprintf("AND c.slug=$%d", idx)
	}
	if marketplace != "" && marketplace != "all" {
		idx++
		params = append(params, marketplace)
		mpF = fmt.Sprintf("AND mp.slug=$%d", idx)
	}

	cq := fmt.Sprintf(`
		SELECT COALESCE(s.country,'Unknown'),
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float8,
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int,
			COUNT(CASE WHEN s.quantity>0 THEN 1 END)::int,
			COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int
		FROM sales s
		JOIN marketplaces mp ON mp.id=s.marketplace_id
		JOIN products p ON p.id=s.product_id
		LEFT JOIN categories c ON c.id=p.category_id
		WHERE s.sale_date>=CURRENT_DATE-$1::int %s %s
		GROUP BY s.country ORDER BY SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END) DESC
	`, catF, mpF)

	cRows, _ := h.db.Query(ctx, cq, params...)
	defer cRows.Close()
	var byCountry []gin.H
	var totalRev float64
	for cRows.Next() {
		var country string
		var rev float64
		var qty, orders, returns int
		cRows.Scan(&country, &rev, &qty, &orders, &returns)
		rr := 0.0
		if (qty + returns) > 0 {
			rr = round2(float64(returns) / float64(qty+returns) * 100)
		}
		totalRev += rev
		byCountry = append(byCountry, gin.H{"country": country, "revenue": round2(rev), "quantity": qty, "orders": orders, "returns": returns, "return_rate": rr})
	}
	if byCountry == nil {
		byCountry = []gin.H{}
	}

	wq := fmt.Sprintf(`
		SELECT COALESCE(s.warehouse,'Unknown'),
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float8,
			COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int,
			COUNT(CASE WHEN s.quantity>0 THEN 1 END)::int,
			COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int
		FROM sales s
		JOIN marketplaces mp ON mp.id=s.marketplace_id
		JOIN products p ON p.id=s.product_id
		LEFT JOIN categories c ON c.id=p.category_id
		WHERE s.sale_date>=CURRENT_DATE-$1::int %s %s
		GROUP BY s.warehouse ORDER BY SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END) DESC
	`, catF, mpF)

	wRows, _ := h.db.Query(ctx, wq, params...)
	defer wRows.Close()
	var byWarehouse []gin.H
	for wRows.Next() {
		var wh string
		var rev float64
		var qty, orders, returns int
		wRows.Scan(&wh, &rev, &qty, &orders, &returns)
		byWarehouse = append(byWarehouse, gin.H{"warehouse": wh, "revenue": round2(rev), "quantity": qty, "orders": orders, "returns": returns})
	}
	if byWarehouse == nil {
		byWarehouse = []gin.H{}
	}

	countries := 0
	for _, cc := range byCountry {
		if cc["country"] != "Unknown" {
			countries++
		}
	}
	warehouses := 0
	for _, ww := range byWarehouse {
		if ww["warehouse"] != "Unknown" {
			warehouses++
		}
	}
	topCountry := "-"
	if len(byCountry) > 0 {
		topCountry = byCountry[0]["country"].(string)
	}
	topWh := "-"
	if len(byWarehouse) > 0 {
		topWh = byWarehouse[0]["warehouse"].(string)
	}

	c.JSON(http.StatusOK, gin.H{
		"period":       period,
		"by_country":   byCountry,
		"by_warehouse": byWarehouse,
		"summary": gin.H{
			"countries": countries, "warehouses": warehouses,
			"total_revenue": round2(totalRev),
			"top_country": topCountry, "top_warehouse": topWh,
		},
	})
}
