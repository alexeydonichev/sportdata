package handlers

import (
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetFinanceFull(c *gin.Context) {
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
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN COALESCE(p.cost_price,0)*s.quantity ELSE 0 END), 0)
		%s %s`, j, w)

	err := h.db.QueryRow(ctx, q, a...).Scan(
		&grossRevenue, &forPay, &commission, &logistics, &acquiring, &storage,
		&penalty, &deduction, &acceptance, &returnLogistics,
		&returnsAmount, &netProfit, &cogs,
	)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}

	netRevenue := grossRevenue - returnsAmount

	var prevGrossRev, prevNetProf, prevComm, prevLogi float64
	pq := fmt.Sprintf(`SELECT
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0),
		COALESCE(SUM(s.net_profit), 0),
		COALESCE(SUM(s.commission), 0),
		COALESCE(SUM(s.logistics_cost), 0)
		%s %s`, j, pw)
	_ = h.db.QueryRow(ctx, pq, pa...).Scan(&prevGrossRev, &prevNetProf, &prevComm, &prevLogi)

	wq := fmt.Sprintf(`SELECT date_trunc('week', s.sale_date)::date,
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0),
		COALESCE(SUM(s.for_pay), 0),
		COALESCE(SUM(s.commission), 0),
		COALESCE(SUM(s.logistics_cost), 0),
		COALESCE(SUM(s.storage_fee), 0),
		COALESCE(SUM(s.penalty), 0),
		COALESCE(SUM(s.net_profit), 0)
		%s %s GROUP BY date_trunc('week', s.sale_date)::date
		ORDER BY date_trunc('week', s.sale_date)::date`, j, w)
	wRows, _ := h.db.Query(ctx, wq, a...)
	var weekly []gin.H
	if wRows != nil {
		defer wRows.Close()
		for wRows.Next() {
			var wk time.Time
			var wr, wp, wc, wl, ws, wpen, wpr float64
			if wRows.Scan(&wk, &wr, &wp, &wc, &wl, &ws, &wpen, &wpr) == nil {
				weekly = append(weekly, gin.H{
					"week": wk.Format("2006-01-02"), "revenue": round2(wr),
					"for_pay": round2(wp), "commission": round2(wc),
					"logistics": round2(wl), "storage": round2(ws),
					"penalty": round2(wpen), "net_profit": round2(wpr),
				})
			}
		}
	}
	if weekly == nil { weekly = []gin.H{} }

	cq := fmt.Sprintf(`SELECT COALESCE(c.name,'Без категории'), COALESCE(c.slug,'uncategorized'),
		COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0),
		COALESCE(SUM(s.commission), 0),
		COALESCE(SUM(s.logistics_cost), 0),
		COALESCE(SUM(s.storage_fee), 0),
		COALESCE(SUM(s.penalty), 0),
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
			var cr, cc, cl, cst, cp, ccogs, cpr float64
			var cu int
			if cRows.Scan(&cn, &cs, &cr, &cc, &cl, &cst, &cp, &ccogs, &cpr, &cu) == nil {
				byCat = append(byCat, gin.H{
					"category": cn, "slug": cs, "revenue": round2(cr),
					"commission": round2(cc), "logistics": round2(cl),
					"storage": round2(cst), "penalty": round2(cp),
					"cogs": round2(ccogs), "net_profit": round2(cpr), "units": cu,
				})
			}
		}
	}
	if byCat == nil { byCat = []gin.H{} }

	var warnings []string
	if grossRevenue > 0 && pct(commission, grossRevenue) > 25 {
		warnings = append(warnings, fmt.Sprintf("Комиссия МП: %.1f%% — выше нормы", pct(commission, grossRevenue)))
	}
	if grossRevenue > 0 && pct(returnsAmount, grossRevenue) > 10 {
		warnings = append(warnings, fmt.Sprintf("Возвраты: %.1f%% от выручки", pct(returnsAmount, grossRevenue)))
	}
	if grossRevenue > 0 && pct(logistics, grossRevenue) > 15 {
		warnings = append(warnings, fmt.Sprintf("Логистика: %.1f%% от выручки", pct(logistics, grossRevenue)))
	}
	if grossRevenue > 0 && pct(storage, grossRevenue) > 5 {
		warnings = append(warnings, fmt.Sprintf("Хранение: %.1f%% от выручки", pct(storage, grossRevenue)))
	}
	if deduction > 10000 {
		warnings = append(warnings, fmt.Sprintf("Удержания за период: %.0f ₽", deduction))
	}
	if netProfit < 0 {
		warnings = append(warnings, "Бизнес убыточен за период!")
	}
	if warnings == nil { warnings = []string{} }

	c.JSON(200, gin.H{
		"period": period,
		"pnl": gin.H{
			"gross_revenue": round2(grossRevenue), "returns_amount": round2(returnsAmount),
			"net_revenue": round2(netRevenue), "for_pay": round2(forPay),
			"commission": round2(commission), "logistics": round2(logistics),
			"acquiring": round2(acquiring), "storage": round2(storage),
			"penalty": round2(penalty), "deduction": round2(deduction),
			"acceptance": round2(acceptance), "return_logistics": round2(returnLogistics),
			"additional_payment": 0.0, "cogs": round2(cogs), "net_profit": round2(netProfit),
		},
		"margins": gin.H{
			"gross_margin": round2(pct(netRevenue-cogs, netRevenue)),
			"net_margin": round2(pct(netProfit, grossRevenue)),
			"commission_pct": round2(pct(commission, grossRevenue)),
			"logistics_pct": round2(pct(logistics, grossRevenue)),
			"return_rate": round2(pct(returnsAmount, grossRevenue)),
		},
		"changes": gin.H{
			"gross_revenue": changePct(grossRevenue, prevGrossRev),
			"commission": changePct(commission, prevComm),
			"logistics": changePct(logistics, prevLogi),
			"net_profit": changePct(netProfit, prevNetProf),
		},
		"weekly": weekly, "by_category": byCat, "warnings": warnings,
	})
}
