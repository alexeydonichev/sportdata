package handlers

import (
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetPnLFull(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "30d")
	catSlug := c.Query("category")
	mpSlug := c.Query("marketplace")

	dateFrom, dateTo := h.parsePeriod(period)
	prevFrom, prevTo := prevPeriod(dateFrom, dateTo)

	j := ` FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id`

	w, a := buildSalesWhere(dateFrom, dateTo, catSlug, mpSlug)
	pw, pa := buildSalesWherePrev(prevFrom, prevTo, catSlug, mpSlug)

	var grossRevenue, forPay, commission, logistics, acquiring, storage float64
	var penalty, deduction, acceptance, returnLogistics float64
	var returnsAmount, netProfit, cogs float64
	var unitsSold, unitsReturned int

	q := fmt.Sprintf(`SELECT
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0),
		COALESCE(SUM(s.for_pay), 0),
		COALESCE(SUM(s.commission), 0),
		COALESCE(SUM(s.logistics_cost), 0),
		COALESCE(SUM(s.acquiring_fee), 0),
		COALESCE(SUM(s.storage_fee), 0),
		COALESCE(SUM(s.penalty), 0),
		COALESCE(SUM(s.deduction), 0),
		COALESCE(SUM(s.acceptance), 0),
		COALESCE(SUM(s.rebill_logistic_cost), 0),
		COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0),
		COALESCE(SUM(s.net_profit), 0),
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN COALESCE(p.cost_price,0) * s.quantity ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)
		%s %s`, j, w)

	err := h.db.QueryRow(ctx, q, a...).Scan(
		&grossRevenue, &forPay, &commission, &logistics, &acquiring, &storage,
		&penalty, &deduction, &acceptance, &returnLogistics,
		&returnsAmount, &netProfit, &cogs, &unitsSold, &unitsReturned,
	)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}

	netRevenue := grossRevenue - returnsAmount
	grossProfit := netRevenue - cogs
	operatingExpenses := commission + logistics + storage + acquiring + penalty + deduction + acceptance + returnLogistics
	operatingProfit := grossProfit - operatingExpenses
	calcNetProfit := operatingProfit

	var prevGrossRev, prevNetProf, prevComm, prevLogi, prevCogs, prevReturns float64
	pq := fmt.Sprintf(`SELECT
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0),
		COALESCE(SUM(s.net_profit), 0),
		COALESCE(SUM(s.commission), 0),
		COALESCE(SUM(s.logistics_cost), 0),
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN COALESCE(p.cost_price,0) * s.quantity ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)
		%s %s`, j, pw)
	h.db.QueryRow(ctx, pq, pa...).Scan(&prevGrossRev, &prevNetProf, &prevComm, &prevLogi, &prevCogs, &prevReturns)

	prevNetRev := prevGrossRev - prevReturns
	prevGrossProfit := prevNetRev - prevCogs
	prevOpProfit := prevGrossProfit - prevComm - prevLogi

	var activeSKUs int
	skuQ := fmt.Sprintf(`SELECT COUNT(DISTINCT p.id) %s %s AND s.quantity > 0`, j, w)
	h.db.QueryRow(ctx, skuQ, a...).Scan(&activeSKUs)

	dq := fmt.Sprintf(`SELECT s.sale_date,
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0),
		COALESCE(SUM(s.commission), 0),
		COALESCE(SUM(s.logistics_cost), 0),
		COALESCE(SUM(s.net_profit), 0)
		%s %s GROUP BY s.sale_date ORDER BY s.sale_date`, j, w)
	dRows, _ := h.db.Query(ctx, dq, a...)
	var daily []gin.H
	if dRows != nil {
		defer dRows.Close()
		for dRows.Next() {
			var d time.Time
			var r, ret, cm, lg, pr float64
			if dRows.Scan(&d, &r, &ret, &cm, &lg, &pr) == nil {
				daily = append(daily, gin.H{
					"date": d.Format("2006-01-02"), "revenue": round2(r),
					"returns": round2(ret), "commission": round2(cm),
					"logistics": round2(lg), "profit": round2(pr),
				})
			}
		}
	}
	if daily == nil { daily = []gin.H{} }

	cq := fmt.Sprintf(`SELECT COALESCE(c.name,'Без категории'), COALESCE(c.slug,'uncategorized'),
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0),
		COALESCE(SUM(s.commission), 0), COALESCE(SUM(s.logistics_cost), 0),
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN COALESCE(p.cost_price,0)*s.quantity ELSE 0 END), 0),
		COALESCE(SUM(s.net_profit), 0),
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)
		%s %s GROUP BY c.name, c.slug ORDER BY SUM(s.revenue) DESC NULLS LAST`, j, w)
	cRows, _ := h.db.Query(ctx, cq, a...)
	var byCat []gin.H
	if cRows != nil {
		defer cRows.Close()
		for cRows.Next() {
			var cn, cs string
			var cr, cc, cl, ccogs, cpr float64
			var cu int
			if cRows.Scan(&cn, &cs, &cr, &cc, &cl, &ccogs, &cpr, &cu) == nil {
				byCat = append(byCat, gin.H{
					"category": cn, "slug": cs, "revenue": round2(cr),
					"commission": round2(cc), "logistics": round2(cl),
					"cogs": round2(ccogs), "profit": round2(cpr), "units": cu,
				})
			}
		}
	}
	if byCat == nil { byCat = []gin.H{} }

	var warnings []string
	if grossRevenue > 0 && pct(commission, grossRevenue) > 25 {
		warnings = append(warnings, fmt.Sprintf("Комиссия МП: %.1f%% от выручки — выше нормы", pct(commission, grossRevenue)))
	}
	if grossRevenue > 0 && pct(returnsAmount, grossRevenue) > 10 {
		warnings = append(warnings, fmt.Sprintf("Возвраты: %.1f%% от выручки", pct(returnsAmount, grossRevenue)))
	}
	if grossRevenue > 0 && pct(logistics, grossRevenue) > 15 {
		warnings = append(warnings, fmt.Sprintf("Логистика: %.1f%% от выручки", pct(logistics, grossRevenue)))
	}
	if calcNetProfit < 0 {
		warnings = append(warnings, "Бизнес убыточен за выбранный период!")
	}
	if warnings == nil { warnings = []string{} }

	grossMargin := pct(grossProfit, netRevenue)
	opMargin := pct(operatingProfit, netRevenue)
	netMargin := pct(calcNetProfit, netRevenue)
	returnRate := pct(float64(unitsReturned), float64(unitsSold+unitsReturned))
	avgCheck := div(grossRevenue, float64(unitsSold))
	avgProfitUnit := div(calcNetProfit, float64(unitsSold))

	c.JSON(200, gin.H{
		"period": period,
		"pnl": gin.H{
			"gross_revenue": round2(grossRevenue), "returns_amount": round2(returnsAmount),
			"net_revenue": round2(netRevenue), "for_pay": round2(forPay),
			"cogs": round2(cogs), "gross_profit": round2(grossProfit),
			"commission": round2(commission), "logistics": round2(logistics),
			"acquiring": round2(acquiring), "storage": round2(storage),
			"penalty": round2(penalty), "deduction": round2(deduction),
			"acceptance": round2(acceptance), "return_logistics": round2(returnLogistics),
			"additional_payment": 0.0, "operating_expenses": round2(operatingExpenses),
			"operating_profit": round2(operatingProfit), "advertising": 0.0,
			"net_profit": round2(calcNetProfit),
		},
		"margins": gin.H{
			"gross_margin": round2(grossMargin), "operating_margin": round2(opMargin),
			"net_margin": round2(netMargin), "commission_pct": round2(pct(commission, grossRevenue)),
			"logistics_pct": round2(pct(logistics, grossRevenue)), "return_rate": round2(returnRate),
		},
		"metrics": gin.H{
			"units_sold": unitsSold, "units_returned": unitsReturned,
			"active_skus": activeSKUs, "avg_check": round2(avgCheck),
			"avg_profit_per_unit": round2(avgProfitUnit),
		},
		"changes": gin.H{
			"gross_revenue": changePct(grossRevenue, prevGrossRev),
			"net_revenue": changePct(netRevenue, prevNetRev),
			"cogs": changePct(cogs, prevCogs), "gross_profit": changePct(grossProfit, prevGrossProfit),
			"commission": changePct(commission, prevComm), "logistics": changePct(logistics, prevLogi),
			"operating_profit": changePct(operatingProfit, prevOpProfit),
			"net_profit": changePct(calcNetProfit, prevNetProf),
		},
		"warnings": warnings, "daily": daily, "by_category": byCat,
	})
}
