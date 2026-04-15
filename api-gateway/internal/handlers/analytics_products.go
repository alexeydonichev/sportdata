package handlers

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetProductsAnalytics(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	days := parseDays(period)
	category := c.Query("category")
	marketplace := c.Query("marketplace")
	sort := c.DefaultQuery("sort", "revenue")
	limit := 50

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

	orderCol := "revenue"
	switch sort {
	case "quantity":
		orderCol = "qty"
	case "profit":
		orderCol = "profit"
	case "returns":
		orderCol = "ret"
	}

	q := fmt.Sprintf(`
		WITH cur AS (
			SELECT s.product_id,
				COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float8 AS revenue,
				COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS qty,
				COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.net_profit ELSE 0 END),0)::float8 AS profit,
				COUNT(CASE WHEN s.quantity>0 THEN 1 END)::int AS orders,
				COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int AS ret
			FROM sales s
			JOIN marketplaces mp ON mp.id=s.marketplace_id
			JOIN products p ON p.id=s.product_id
			LEFT JOIN categories c ON c.id=p.category_id
			WHERE s.sale_date>=CURRENT_DATE-$1::int %s %s
			GROUP BY s.product_id
		)
		SELECT p.id, p.name, p.sku, p.brand, COALESCE(c.name,'N/A') AS cat_name,
			cur.revenue, cur.qty, cur.profit, cur.orders, cur.ret
		FROM cur
		JOIN products p ON p.id=cur.product_id
		LEFT JOIN categories c ON c.id=p.category_id
		ORDER BY cur.%s DESC LIMIT %d
	`, catF, mpF, orderCol, limit)

	rows, err := h.db.Query(ctx, q, params...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var products []gin.H
	for rows.Next() {
		var pid int
		var nm, sku, brand, cat string
		var rev, profit float64
		var qty, orders, ret int
		rows.Scan(&pid, &nm, &sku, &brand, &cat, &rev, &qty, &profit, &orders, &ret)
		margin := 0.0
		if rev > 0 {
			margin = profit / rev * 100
		}
		rr := 0.0
		if (qty + ret) > 0 {
			rr = float64(ret) / float64(qty+ret) * 100
		}
		avgPrice := 0.0
		if qty > 0 {
			avgPrice = rev / float64(qty)
		}
		products = append(products, gin.H{
			"product_id": pid, "name": nm, "sku": sku, "brand": brand, "category": cat,
			"revenue": round2(rev), "quantity": qty, "profit": round2(profit),
			"margin": round2(margin), "orders": orders, "returns": ret,
			"return_rate": round2(rr), "avg_price": round2(avgPrice),
		})
	}
	if products == nil {
		products = []gin.H{}
	}

	// Summary
	var totalProducts int
	_ = h.db.QueryRow(ctx, fmt.Sprintf(`
		SELECT COUNT(DISTINCT s.product_id)
		FROM sales s
		JOIN marketplaces mp ON mp.id=s.marketplace_id
		JOIN products p ON p.id=s.product_id
		LEFT JOIN categories c ON c.id=p.category_id
		WHERE s.sale_date>=CURRENT_DATE-$1::int AND s.quantity>0 %s %s
	`, catF, mpF), params...).Scan(&totalProducts)

	c.JSON(http.StatusOK, gin.H{
		"period":         period,
		"products":       products,
		"total_products": totalProducts,
		"sort":           sort,
	})
}
