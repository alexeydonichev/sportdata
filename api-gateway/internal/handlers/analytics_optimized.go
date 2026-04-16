package handlers

import (
	"fmt"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

func buildQ(sel, join, where, suffix string) string {
	return fmt.Sprintf("%s%s%s%s", sel, join, where, suffix)
}

func (h *Handler) GetAnalyticsOptimized(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "30d")
	catSlug := c.Query("category")
	mpSlug := c.Query("marketplace")
	dateFrom, dateTo := h.parsePeriod(period)

	w, a := buildSalesWhere(dateFrom, dateTo, catSlug, mpSlug)

	j := " FROM sales s LEFT JOIN products p ON p.id = s.product_id LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN marketplaces m ON m.id = s.marketplace_id"

	var wg sync.WaitGroup
	var mu sync.Mutex
	var byCat, byMP, trend []gin.H
	var costs gin.H

	wg.Add(4)

	go func() {
		defer wg.Done()
		q := buildQ("SELECT c.slug, c.name, COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.quantity),0)", j, w, " GROUP BY c.slug, c.name ORDER BY SUM(s.revenue) DESC NULLS LAST")
		rows, err := h.db.Query(ctx, q, a...)
		if err != nil {
			return
		}
		defer rows.Close()
		type cr struct {
			slug, name string
			rev, prof  float64
			qty        int
		}
		var tmp []cr
		var lr float64
		for rows.Next() {
			var r cr
			if rows.Scan(&r.slug, &r.name, &r.rev, &r.prof, &r.qty) == nil {
				tmp = append(tmp, r)
				lr += r.rev
			}
		}
		res := make([]gin.H, 0, len(tmp))
		for _, r := range tmp {
			res = append(res, gin.H{
				"category": r.slug, "name": r.name,
				"revenue": round2(r.rev), "profit": round2(r.prof),
				"quantity": r.qty, "share_pct": round2(pct(r.rev, lr)),
			})
		}
		mu.Lock()
		byCat = res
		mu.Unlock()
	}()

	go func() {
		defer wg.Done()
		q := buildQ("SELECT m.slug, m.name, COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.quantity),0)", j, w, " GROUP BY m.slug, m.name ORDER BY SUM(s.revenue) DESC NULLS LAST")
		rows, err := h.db.Query(ctx, q, a...)
		if err != nil {
			return
		}
		defer rows.Close()
		var items []gin.H
		var lr float64
		for rows.Next() {
			var sl, nm string
			var r, p float64
			var qt int
			if rows.Scan(&sl, &nm, &r, &p, &qt) == nil {
				lr += r
				items = append(items, gin.H{
					"marketplace": sl, "name": nm,
					"revenue": round2(r), "profit": round2(p),
					"quantity": qt, "_r": r,
				})
			}
		}
		for _, m := range items {
			rv := m["_r"].(float64)
			m["share_pct"] = round2(pct(rv, lr))
			delete(m, "_r")
		}
		if items == nil {
			items = []gin.H{}
		}
		mu.Lock()
		byMP = items
		mu.Unlock()
	}()

	go func() {
		defer wg.Done()
		q := buildQ("SELECT s.sale_date, COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.commission),0), COALESCE(SUM(s.logistics_cost),0), COUNT(*), COALESCE(SUM(s.quantity),0)", j, w, " GROUP BY s.sale_date ORDER BY s.sale_date")
		rows, err := h.db.Query(ctx, q, a...)
		if err != nil {
			return
		}
		defer rows.Close()
		var items []gin.H
		for rows.Next() {
			var d time.Time
			var r, p, cm, lg float64
			var o, qt int
			if rows.Scan(&d, &r, &p, &cm, &lg, &o, &qt) == nil {
				items = append(items, gin.H{
					"date":       d.Format("2006-01-02"),
					"revenue":    round2(r),
					"profit":     round2(p),
					"commission": round2(cm),
					"logistics":  round2(lg),
					"orders":     o,
					"quantity":   qt,
					"margin_pct": round2(pct(p, r)),
				})
			}
		}
		if items == nil {
			items = []gin.H{}
		}
		mu.Lock()
		trend = items
		mu.Unlock()
	}()

	go func() {
		defer wg.Done()
		q := buildQ("SELECT COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0), COALESCE(SUM(s.commission),0), COALESCE(SUM(s.logistics_cost),0), COALESCE(SUM(p.cost_price * s.quantity),0)", j, w, "")
		var totRev, totProf, totComm, totLogi, totCost float64
		if err := h.db.QueryRow(ctx, q, a...).Scan(&totRev, &totProf, &totComm, &totLogi, &totCost); err != nil {
			/* costs query failed */
		}
		mu.Lock()
		costs = gin.H{
			"total_revenue":  round2(totRev),
			"cost_price":     round2(totCost),
			"cost_price_pct": round2(pct(totCost, totRev)),
			"commission":     round2(totComm),
			"commission_pct": round2(pct(totComm, totRev)),
			"logistics":      round2(totLogi),
			"logistics_pct":  round2(pct(totLogi, totRev)),
			"profit":         round2(totProf),
			"profit_pct":     round2(pct(totProf, totRev)),
		}
		mu.Unlock()
	}()

	wg.Wait()

	if byCat == nil {
		byCat = []gin.H{}
	}
	if byMP == nil {
		byMP = []gin.H{}
	}
	if trend == nil {
		trend = []gin.H{}
	}
	if costs == nil {
		costs = gin.H{}
	}

	c.JSON(200, gin.H{
		"period":         period,
		"date_from":      dateFrom,
		"date_to":        dateTo,
		"by_category":    byCat,
		"by_marketplace": byMP,
		"daily_trend":    trend,
		"cost_breakdown": costs,
	})
}
