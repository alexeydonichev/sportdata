package handlers

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetReturnsAnalytics(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	days := parseDays(period)
	category := c.Query("category")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	params := []interface{}{days}
	catF := ""
	if category != "" && category != "all" {
		params = append(params, category)
		catF = fmt.Sprintf("AND c.slug=$%d", len(params))
	}

	var totalSales int
	var totalRevenue, totalProfit float64
	_ = h.db.QueryRow(ctx, fmt.Sprintf(`
		SELECT COALESCE(SUM(s.quantity),0)::int, COALESCE(SUM(s.revenue),0)::float8, COALESCE(SUM(s.net_profit),0)::float8
		FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id
		WHERE s.sale_date>=CURRENT_DATE-$1::int AND s.quantity>0 %s
	`, catF), params...).Scan(&totalSales, &totalRevenue, &totalProfit)

	var curReturns int
	var curRetAmount, curLogCost float64
	_ = h.db.QueryRow(ctx, fmt.Sprintf(`
		SELECT COALESCE(SUM(r.quantity),0)::int, COALESCE(SUM(r.return_amount),0)::float8, COALESCE(SUM(r.logistics_cost),0)::float8
		FROM returns r JOIN products p ON p.id=r.product_id LEFT JOIN categories c ON c.id=p.category_id
		WHERE r.return_date>=CURRENT_DATE-$1::int %s
	`, catF), params...).Scan(&curReturns, &curRetAmount, &curLogCost)

	var prevReturns int
	var prevRetAmount float64
	var prevSales int
	_ = h.db.QueryRow(ctx, fmt.Sprintf(`
		SELECT COALESCE(SUM(r.quantity),0)::int, COALESCE(SUM(r.return_amount),0)::float8
		FROM returns r JOIN products p ON p.id=r.product_id LEFT JOIN categories c ON c.id=p.category_id
		WHERE r.return_date>=CURRENT_DATE-($1::int*2) AND r.return_date<CURRENT_DATE-$1::int %s
	`, catF), params...).Scan(&prevReturns, &prevRetAmount)
	_ = h.db.QueryRow(ctx, fmt.Sprintf(`
		SELECT COALESCE(SUM(s.quantity),0)::int
		FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id
		WHERE s.sale_date>=CURRENT_DATE-($1::int*2) AND s.sale_date<CURRENT_DATE-$1::int AND s.quantity>0 %s
	`, catF), params...).Scan(&prevSales)

	curRate := 0.0
	if (totalSales + curReturns) > 0 {
		curRate = float64(curReturns) / float64(totalSales+curReturns) * 100
	}
	prevRate := 0.0
	if (prevSales + prevReturns) > 0 {
		prevRate = float64(prevReturns) / float64(prevSales+prevReturns) * 100
	}
	avgProfit := 0.0
	if totalSales > 0 {
		avgProfit = totalProfit / float64(totalSales)
	}
	lostProfit := avgProfit * float64(curReturns)

	dRows, _ := h.db.Query(ctx, fmt.Sprintf(`
		WITH ds AS (
			SELECT s.sale_date AS d, COALESCE(SUM(s.quantity),0)::int AS sales
			FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id
			WHERE s.sale_date>=CURRENT_DATE-$1::int AND s.quantity>0 %s GROUP BY s.sale_date
		), dr AS (
			SELECT r.return_date AS d, COALESCE(SUM(r.quantity),0)::int AS returns
			FROM returns r JOIN products p ON p.id=r.product_id LEFT JOIN categories c ON c.id=p.category_id
			WHERE r.return_date>=CURRENT_DATE-$1::int %s GROUP BY r.return_date
		)
		SELECT COALESCE(ds.d,dr.d)::text, COALESCE(ds.sales,0), COALESCE(dr.returns,0)
		FROM ds FULL OUTER JOIN dr ON ds.d=dr.d ORDER BY 1
	`, catF, catF), params...)
	var daily []gin.H
	if dRows != nil {
		defer dRows.Close()
		for dRows.Next() {
			var dt string
			var s, r int
			dRows.Scan(&dt, &s, &r)
			rr := 0.0
			if (s + r) > 0 {
				rr = round2(float64(r) / float64(s+r) * 100)
			}
			daily = append(daily, gin.H{"date": dt, "sales": s, "returns": r, "return_rate": rr})
		}
	}
	if daily == nil {
		daily = []gin.H{}
	}

	pRows, _ := h.db.Query(ctx, `
		WITH ps AS (
			SELECT product_id, SUM(quantity)::int AS sq, SUM(revenue)::float8 AS sa
			FROM sales WHERE sale_date>=CURRENT_DATE-$1::int AND quantity>0 GROUP BY product_id
		), pr AS (
			SELECT product_id, SUM(quantity)::int AS rq, COALESCE(SUM(return_amount),0)::float8 AS ra
			FROM returns WHERE return_date>=CURRENT_DATE-$1::int GROUP BY product_id
		)
		SELECT p.id, p.name, p.sku, COALESCE(c.name,'N/A'),
			COALESCE(ps.sq,0), COALESCE(pr.rq,0), COALESCE(pr.ra,0)
		FROM pr JOIN products p ON p.id=pr.product_id
		LEFT JOIN categories c ON c.id=p.category_id
		LEFT JOIN ps ON ps.product_id=p.id
		ORDER BY pr.rq DESC LIMIT 50
	`, days)
	var byProduct []gin.H
	if pRows != nil {
		defer pRows.Close()
		for pRows.Next() {
			var pid int
			var nm, sku, cat string
			var sq, rq int
			var ra float64
			pRows.Scan(&pid, &nm, &sku, &cat, &sq, &rq, &ra)
			rr := 0.0
			if (sq + rq) > 0 {
				rr = round2(float64(rq) / float64(sq+rq) * 100)
			}
			byProduct = append(byProduct, gin.H{
				"product_id": pid, "name": nm, "sku": sku, "category": cat,
				"sales_qty": sq, "return_qty": rq, "return_rate": rr, "return_amount": round2(ra),
			})
		}
	}
	if byProduct == nil {
		byProduct = []gin.H{}
	}

	catRows, _ := h.db.Query(ctx, `
		WITH cs AS (
			SELECT p.category_id, SUM(s.quantity)::int AS sq
			FROM sales s JOIN products p ON p.id=s.product_id
			WHERE s.sale_date>=CURRENT_DATE-$1::int AND s.quantity>0 GROUP BY p.category_id
		), cr AS (
			SELECT p.category_id, SUM(r.quantity)::int AS rq, COALESCE(SUM(r.return_amount),0)::float8 AS ra
			FROM returns r JOIN products p ON p.id=r.product_id
			WHERE r.return_date>=CURRENT_DATE-$1::int GROUP BY p.category_id
		)
		SELECT COALESCE(c.name,'N/A'), COALESCE(cs.sq,0), COALESCE(cr.rq,0), COALESCE(cr.ra,0)
		FROM cr LEFT JOIN categories c ON c.id=cr.category_id
		LEFT JOIN cs ON cs.category_id=cr.category_id
		ORDER BY cr.rq DESC
	`, days)
	var byCategory []gin.H
	if catRows != nil {
		defer catRows.Close()
		for catRows.Next() {
			var cn string
			var sq, rq int
			var ra float64
			catRows.Scan(&cn, &sq, &rq, &ra)
			rr := 0.0
			if (sq + rq) > 0 {
				rr = round2(float64(rq) / float64(sq+rq) * 100)
			}
			byCategory = append(byCategory, gin.H{"category": cn, "sales_qty": sq, "return_qty": rq, "return_rate": rr, "return_amount": round2(ra)})
		}
	}
	if byCategory == nil {
		byCategory = []gin.H{}
	}

	whRows, _ := h.db.Query(ctx, fmt.Sprintf(`
		SELECT COALESCE(r.warehouse,'Unknown'), COALESCE(SUM(r.quantity),0)::int, COALESCE(SUM(r.return_amount),0)::float8
		FROM returns r JOIN products p ON p.id=r.product_id LEFT JOIN categories c ON c.id=p.category_id
		WHERE r.return_date>=CURRENT_DATE-$1::int %s
		GROUP BY r.warehouse ORDER BY SUM(r.quantity) DESC
	`, catF), params...)
	var byWarehouse []gin.H
	if whRows != nil {
		defer whRows.Close()
		for whRows.Next() {
			var wh string
			var rq int
			var ra float64
			whRows.Scan(&wh, &rq, &ra)
			byWarehouse = append(byWarehouse, gin.H{"warehouse": wh, "return_qty": rq, "return_amount": round2(ra)})
		}
	}
	if byWarehouse == nil {
		byWarehouse = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{
		"period": period,
		"summary": gin.H{
			"total_returns":    curReturns,
			"total_sales":      totalSales,
			"return_rate":      round2(curRate),
			"return_amount":    round2(curRetAmount),
			"lost_profit":      round2(lostProfit),
			"return_logistics": round2(curLogCost),
		},
		"changes": gin.H{
			"returns":       pctChange(float64(curReturns), float64(prevReturns)),
			"return_rate":   pctChange(curRate, prevRate),
			"return_amount": pctChange(curRetAmount, prevRetAmount),
		},
		"daily":        daily,
		"by_product":   byProduct,
		"by_category":  byCategory,
		"by_warehouse": byWarehouse,
	})
}
