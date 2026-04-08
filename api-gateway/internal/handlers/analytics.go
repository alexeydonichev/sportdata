package handlers

import (
	"context"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetPnL(c *gin.Context) {
	ctx := context.Background()
	period := c.DefaultQuery("period", "30d")
	categorySlug := c.Query("category")
	marketplaceSlug := c.Query("marketplace")
	dateFrom, dateTo := parsePeriod(period)
	prevFrom, prevTo := prevPeriod(dateFrom, dateTo)

	joinClause := `FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id`

	whereClause, args := buildSalesWhere(dateFrom, dateTo, categorySlug, marketplaceSlug)
	prevWhere, prevArgs := buildSalesWherePrev(prevFrom, prevTo, categorySlug, marketplaceSlug)

	// Current period totals
	var revenue, costOfGoods, commission, logistics, profit float64
	var quantity int
	q := fmt.Sprintf(`
		SELECT COALESCE(SUM(s.revenue),0),
			COALESCE(SUM(s.quantity * COALESCE(p.cost_price,0)),0),
			COALESCE(SUM(s.commission),0),
			COALESCE(SUM(s.logistics_cost),0),
			COALESCE(SUM(s.net_profit),0),
			COALESCE(SUM(s.quantity),0)
		%s %s`, joinClause, whereClause)
	h.db.QueryRow(ctx, q, args...).Scan(&revenue, &costOfGoods, &commission, &logistics, &profit, &quantity)

	// Returns (negative quantity sales)
	var returnsAmount float64
	var unitsReturned int
	rq := fmt.Sprintf(`
		SELECT COALESCE(SUM(ABS(s.revenue)),0), COALESCE(SUM(ABS(s.quantity)),0)
		%s %s AND s.quantity < 0`, joinClause, whereClause)
	h.db.QueryRow(ctx, rq, args...).Scan(&returnsAmount, &unitsReturned)

	// Active SKUs
	var activeSkus int
	sq := fmt.Sprintf(`
		SELECT COUNT(DISTINCT s.product_id)
		%s %s AND s.quantity > 0`, joinClause, whereClause)
	h.db.QueryRow(ctx, sq, args...).Scan(&activeSkus)

	// Previous period
	var prevRevenue, prevProfit, prevCogs, prevCommission, prevLogistics float64
	var prevQuantity int
	pq := fmt.Sprintf(`
		SELECT COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
			COALESCE(SUM(s.quantity * COALESCE(p.cost_price,0)),0),
			COALESCE(SUM(s.commission),0), COALESCE(SUM(s.logistics_cost),0),
			COALESCE(SUM(s.quantity),0)
		%s %s`, joinClause, prevWhere)
	h.db.QueryRow(ctx, pq, prevArgs...).Scan(&prevRevenue, &prevProfit, &prevCogs, &prevCommission, &prevLogistics, &prevQuantity)

	// Computed PnL fields
	grossRevenue := revenue
	netRevenue := revenue - returnsAmount
	grossProfit := netRevenue - costOfGoods
	operatingExpenses := commission + logistics
	operatingProfit := grossProfit - operatingExpenses
	netProfit := profit

	grossMargin := pct(grossProfit, netRevenue)
	operatingMargin := pct(operatingProfit, netRevenue)
	netMargin := pct(netProfit, grossRevenue)
	returnRate := pct(returnsAmount, grossRevenue)

	avgCheck := div(grossRevenue, float64(quantity))
	avgProfitPerUnit := div(netProfit, float64(quantity))

	// Previous period computed
	prevNetRevenue := prevRevenue
	prevGrossProfit := prevNetRevenue - prevCogs
	prevOperatingProfit := prevGrossProfit - prevCommission - prevLogistics

	// By category with full breakdown
	catQ := fmt.Sprintf(`
		SELECT COALESCE(c.name, 'Без категории'),
			COALESCE(c.slug, ''),
			COALESCE(SUM(s.revenue),0),
			COALESCE(SUM(s.net_profit),0),
			COALESCE(SUM(s.quantity),0),
			COALESCE(SUM(s.commission),0),
			COALESCE(SUM(s.logistics_cost),0),
			COALESCE(SUM(s.quantity * COALESCE(p.cost_price,0)),0)
		%s %s
		GROUP BY c.name, c.slug ORDER BY SUM(s.revenue) DESC`, joinClause, whereClause)
	catRows, _ := h.db.Query(ctx, catQ, args...)
	var byCategory []gin.H
	if catRows != nil {
		defer catRows.Close()
		for catRows.Next() {
			var cn, cs string
			var r, p, comm, logi, cogs float64
			var qty int
			catRows.Scan(&cn, &cs, &r, &p, &qty, &comm, &logi, &cogs)
			byCategory = append(byCategory, gin.H{
				"category":   cn,
				"slug":       cs,
				"revenue":    round2(r),
				"profit":     round2(p),
				"units":      qty,
				"commission": round2(comm),
				"logistics":  round2(logi),
				"cogs":       round2(cogs),
				"margin_pct": round2(pct(p, r)),
			})
		}
	}
	if byCategory == nil {
		byCategory = []gin.H{}
	}

	// Daily chart
	chartQ := fmt.Sprintf(`
		SELECT s.sale_date,
			COALESCE(SUM(s.revenue),0),
			COALESCE(SUM(s.net_profit),0),
			COALESCE(SUM(s.commission),0),
			COALESCE(SUM(s.logistics_cost),0),
			COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END),0)
		%s %s
		GROUP BY s.sale_date ORDER BY s.sale_date`, joinClause, whereClause)
	chartRows, _ := h.db.Query(ctx, chartQ, args...)
	var daily []gin.H
	if chartRows != nil {
		defer chartRows.Close()
		for chartRows.Next() {
			var d time.Time
			var r, p, co, lo, ret float64
			chartRows.Scan(&d, &r, &p, &co, &lo, &ret)
			daily = append(daily, gin.H{
				"date":       d.Format("2006-01-02"),
				"revenue":    round2(r),
				"profit":     round2(p),
				"commission": round2(co),
				"logistics":  round2(lo),
				"returns":    round2(ret),
			})
		}
	}
	if daily == nil {
		daily = []gin.H{}
	}

	c.JSON(200, gin.H{
		"period":    period,
		"date_from": dateFrom,
		"date_to":   dateTo,
		"pnl": gin.H{
			"gross_revenue":      round2(grossRevenue),
			"returns_amount":     round2(returnsAmount),
			"net_revenue":        round2(netRevenue),
			"cogs":               round2(costOfGoods),
			"gross_profit":       round2(grossProfit),
			"commission":         round2(commission),
			"logistics":          round2(logistics),
			"operating_expenses": round2(operatingExpenses),
			"operating_profit":   round2(operatingProfit),
			"advertising":        0,
			"net_profit":         round2(netProfit),
		},
		"margins": gin.H{
			"gross_margin":     round2(grossMargin),
			"operating_margin": round2(operatingMargin),
			"net_margin":       round2(netMargin),
			"return_rate":      round2(returnRate),
		},
		"metrics": gin.H{
			"units_sold":          quantity,
			"units_returned":      unitsReturned,
			"active_skus":         activeSkus,
			"avg_check":           round2(avgCheck),
			"avg_profit_per_unit": round2(avgProfitPerUnit),
		},
		"changes": gin.H{
			"gross_revenue":    changePct(grossRevenue, prevRevenue),
			"net_revenue":      changePct(netRevenue, prevNetRevenue),
			"cogs":             changePct(costOfGoods, prevCogs),
			"gross_profit":     changePct(grossProfit, prevGrossProfit),
			"commission":       changePct(commission, prevCommission),
			"logistics":        changePct(logistics, prevLogistics),
			"operating_profit": changePct(operatingProfit, prevOperatingProfit),
			"net_profit":       changePct(netProfit, prevProfit),
			"revenue":          changePct(revenue, prevRevenue),
			"profit":           changePct(profit, prevProfit),
		},
		"by_category": byCategory,
		"daily":       daily,
	})
}

func (h *Handler) GetABC(c *gin.Context) {
	ctx := context.Background()
	period := c.DefaultQuery("period", "90d")
	categorySlug := c.Query("category")
	marketplaceSlug := c.Query("marketplace")
	dateFrom, dateTo := parsePeriod(period)

	whereClause, args := buildSalesWhere(dateFrom, dateTo, categorySlug, marketplaceSlug)

	var totalRevenue float64
	tq := fmt.Sprintf(`
		SELECT COALESCE(SUM(s.revenue),0)
		FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id
		%s`, whereClause)
	h.db.QueryRow(ctx, tq, args...).Scan(&totalRevenue)

	q := fmt.Sprintf(`
		SELECT p.id::text, p.name, p.sku, COALESCE(c.name, '') as category,
			COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
			COALESCE(SUM(s.quantity),0), COUNT(DISTINCT s.id)
		FROM sales s
		JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id
		%s
		GROUP BY p.id, p.name, p.sku, c.name
		ORDER BY SUM(s.revenue) DESC`, whereClause)

	rows, err := h.db.Query(ctx, q, args...)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	var products []gin.H
	cumShare := 0.0
	var groupA, groupB, groupC []gin.H
	var revenueA, revenueB, revenueC float64

	for rows.Next() {
		var id, name, sku, cat string
		var rev, prof float64
		var qty, orders int
		rows.Scan(&id, &name, &sku, &cat, &rev, &prof, &qty, &orders)
		share := pct(rev, totalRevenue)
		cumShare += share

		grade := "C"
		if cumShare <= 80 {
			grade = "A"
			revenueA += rev
		} else if cumShare <= 95 {
			grade = "B"
			revenueB += rev
		} else {
			revenueC += rev
		}

		item := gin.H{
			"id": id, "name": name, "sku": sku, "category": cat,
			"revenue": round2(rev), "profit": round2(prof),
			"quantity": qty, "orders": orders,
			"share_pct": round2(share), "cumulative_pct": round2(cumShare),
			"grade": grade,
		}
		products = append(products, item)

		switch grade {
		case "A":
			groupA = append(groupA, item)
		case "B":
			groupB = append(groupB, item)
		case "C":
			groupC = append(groupC, item)
		}
	}
	if products == nil {
		products = []gin.H{}
	}

	c.JSON(200, gin.H{
		"period": period, "date_from": dateFrom, "date_to": dateTo,
		"total_revenue": round2(totalRevenue),
		"products":      products,
		"summary": gin.H{
			"A": gin.H{"count": len(groupA), "revenue": round2(revenueA), "share_pct": round2(pct(revenueA, totalRevenue))},
			"B": gin.H{"count": len(groupB), "revenue": round2(revenueB), "share_pct": round2(pct(revenueB, totalRevenue))},
			"C": gin.H{"count": len(groupC), "revenue": round2(revenueC), "share_pct": round2(pct(revenueC, totalRevenue))},
		},
	})
}

func (h *Handler) GetUnitEconomics(c *gin.Context) {
	ctx := context.Background()
	period := c.DefaultQuery("period", "30d")
	categorySlug := c.Query("category")
	marketplaceSlug := c.Query("marketplace")
	dateFrom, dateTo := parsePeriod(period)

	whereClause, args := buildSalesWhere(dateFrom, dateTo, categorySlug, marketplaceSlug)

	q := fmt.Sprintf(`
		SELECT p.id::text, p.name, p.sku, COALESCE(c.name,'') as category,
			COALESCE(p.cost_price, 0) as cost_price,
			COALESCE(AVG(s.revenue / NULLIF(s.quantity, 0)), 0) as avg_price,
			COALESCE(SUM(s.revenue), 0) as revenue,
			COALESCE(SUM(s.net_profit), 0) as profit,
			COALESCE(SUM(s.quantity), 0) as quantity,
			COALESCE(SUM(s.commission), 0) as commission,
			COALESCE(SUM(s.logistics_cost), 0) as logistics,
			COALESCE(SUM(s.quantity * COALESCE(p.cost_price, 0)), 0) as total_cost
		FROM sales s
		JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id
		%s
		GROUP BY p.id, p.name, p.sku, c.name, p.cost_price
		HAVING SUM(s.quantity) > 0
		ORDER BY SUM(s.revenue) DESC
		LIMIT 100`, whereClause)

	rows, err := h.db.Query(ctx, q, args...)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	var products []gin.H
	var totRev, totProf, totComm, totLogi, totCost float64
	var totQty int

	for rows.Next() {
		var id, name, sku, cat string
		var costPrice, avgPrice, rev, prof float64
		var qty int
		var comm, logi, totalCost float64
		rows.Scan(&id, &name, &sku, &cat, &costPrice, &avgPrice, &rev, &prof, &qty, &comm, &logi, &totalCost)

		profitPerUnit := div(prof, float64(qty))
		commPerUnit := div(comm, float64(qty))
		logiPerUnit := div(logi, float64(qty))
		marginPct := pct(prof, rev)

		products = append(products, gin.H{
			"id": id, "name": name, "sku": sku, "category": cat,
			"cost_price": round2(costPrice), "avg_price": round2(avgPrice),
			"revenue": round2(rev), "profit": round2(prof), "quantity": qty,
			"commission": round2(comm), "logistics": round2(logi),
			"profit_per_unit":     round2(profitPerUnit),
			"commission_per_unit": round2(commPerUnit),
			"logistics_per_unit":  round2(logiPerUnit),
			"margin_pct":          round2(marginPct),
		})

		totRev += rev
		totProf += prof
		totComm += comm
		totLogi += logi
		totCost += totalCost
		totQty += qty
	}
	if products == nil {
		products = []gin.H{}
	}

	c.JSON(200, gin.H{
		"period": period, "date_from": dateFrom, "date_to": dateTo,
		"products": products,
		"totals": gin.H{
			"revenue": round2(totRev), "profit": round2(totProf),
			"commission": round2(totComm), "logistics": round2(totLogi),
			"cost_of_goods": round2(totCost), "quantity": totQty,
			"margin_pct":          round2(pct(totProf, totRev)),
			"avg_profit_per_unit": round2(div(totProf, float64(totQty))),
		},
	})
}
