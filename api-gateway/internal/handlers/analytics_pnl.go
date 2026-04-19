package handlers

import (
	"context"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

// GetPnLFull — единый P&L отчёт.
// WB → canonical views (v_pnl_summary + v_pnl_daily).
// Other MPs → legacy путь через sales.
func (h *Handler) GetPnLFull(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	catSlug := c.Query("category")
	mpSlug := c.Query("marketplace")

	dateFrom, dateTo := h.parsePeriod(period)
	prevFrom, prevTo := prevPeriod(dateFrom, dateTo)

	isWB := mpSlug == "" || mpSlug == "all" || mpSlug == "wb" || mpSlug == "wildberries"
	if isWB {
		h.getPnLFullWB(c, period, dateFrom, dateTo, prevFrom, prevTo, catSlug)
		return
	}
	h.getPnLFullLegacy(c, period, dateFrom, dateTo, prevFrom, prevTo, catSlug, mpSlug)
}

// ============================================================
// WB: canonical
// ============================================================
func (h *Handler) getPnLFullWB(
	c *gin.Context,
	period, dateFrom, dateTo, prevFrom, prevTo, catSlug string,
) {
	ctx := c.Request.Context()
	useDaily := catSlug != "" && catSlug != "all"

	var (
		grossRev, returnsAmt, netRev, forPay          float64
		commission, logistics, acquiring, storage     float64
		penalty, deduction, acceptance, addpay        float64
		rewardIncome, cogs, netProfit                 float64
		units                                         int64
	)

	if !useDaily {
		q := `SELECT
			COALESCE(SUM(gross_revenue),0), COALESCE(SUM(returns_amount),0),
			COALESCE(SUM(net_revenue),0),   COALESCE(SUM(for_pay),0),
			COALESCE(SUM(commission),0),    COALESCE(SUM(logistics),0),
			COALESCE(SUM(acquiring),0),     COALESCE(SUM(storage),0),
			COALESCE(SUM(penalty),0),       COALESCE(SUM(deduction),0),
			COALESCE(SUM(acceptance),0),    COALESCE(SUM(additional_payment),0),
			COALESCE(SUM(reward_income),0), COALESCE(SUM(cogs),0),
			COALESCE(SUM(net_profit),0),    COALESCE(SUM(units),0)
			FROM v_pnl_summary
			WHERE date >= $1 AND date <= $2`
		if err := h.db.QueryRow(ctx, q, dateFrom, dateTo).Scan(
			&grossRev, &returnsAmt, &netRev, &forPay,
			&commission, &logistics, &acquiring, &storage,
			&penalty, &deduction, &acceptance, &addpay,
			&rewardIncome, &cogs, &netProfit, &units,
		); err != nil {
			c.JSON(500, gin.H{"error": "pnl_summary: " + err.Error()})
			return
		}
	} else {
		q := `SELECT
			COALESCE(SUM(v.gross_revenue),0), COALESCE(SUM(v.returns_amount),0),
			COALESCE(SUM(v.gross_revenue - v.returns_amount),0),
			COALESCE(SUM(v.for_pay),0),       COALESCE(SUM(v.commission),0),
			COALESCE(SUM(v.logistics),0),     COALESCE(SUM(v.acquiring),0),
			COALESCE(SUM(v.storage),0),       COALESCE(SUM(v.penalty),0),
			COALESCE(SUM(v.deduction),0),     COALESCE(SUM(v.acceptance),0),
			COALESCE(SUM(v.additional_payment),0),
			COALESCE(SUM(v.reward_income),0), COALESCE(SUM(v.cogs),0),
			COALESCE(SUM(
				v.for_pay - v.logistics - v.storage - v.acceptance
				- v.penalty - v.deduction + v.additional_payment
				+ v.reward_income - v.cogs),0),
			COALESCE(SUM(v.units),0)
			FROM v_pnl_daily v
			JOIN categories c ON c.id = v.category_id
			WHERE v.date >= $1 AND v.date <= $2 AND c.slug = $3`
		if err := h.db.QueryRow(ctx, q, dateFrom, dateTo, catSlug).Scan(
			&grossRev, &returnsAmt, &netRev, &forPay,
			&commission, &logistics, &acquiring, &storage,
			&penalty, &deduction, &acceptance, &addpay,
			&rewardIncome, &cogs, &netProfit, &units,
		); err != nil {
			c.JSON(500, gin.H{"error": "pnl_daily: " + err.Error()})
			return
		}
	}

	h.pnlWBContinue(c, ctx, period,
		dateFrom, dateTo, prevFrom, prevTo, catSlug, useDaily,
		grossRev, returnsAmt, netRev, forPay,
		commission, logistics, acquiring, storage,
		penalty, deduction, acceptance, addpay,
		rewardIncome, cogs, netProfit, units)
}

func (h *Handler) pnlWBContinue(
	c *gin.Context, ctx context.Context, period string,
	dateFrom, dateTo, prevFrom, prevTo, catSlug string, useDaily bool,
	grossRev, returnsAmt, netRev, forPay float64,
	commission, logistics, acquiring, storage float64,
	penalty, deduction, acceptance, addpay float64,
	rewardIncome, cogs, netProfit float64, units int64,
) {
	// --- Prev period ---
	var prevGrossRev, prevNetRev, prevCommission, prevLogi, prevCogs, prevNetProfit float64
	if !useDaily {
		pq := `SELECT
			COALESCE(SUM(gross_revenue),0), COALESCE(SUM(net_revenue),0),
			COALESCE(SUM(commission),0),    COALESCE(SUM(logistics),0),
			COALESCE(SUM(cogs),0),          COALESCE(SUM(net_profit),0)
			FROM v_pnl_summary WHERE date >= $1 AND date <= $2`
		_ = h.db.QueryRow(ctx, pq, prevFrom, prevTo).Scan(
			&prevGrossRev, &prevNetRev, &prevCommission, &prevLogi, &prevCogs, &prevNetProfit)
	} else {
		pq := `SELECT
			COALESCE(SUM(v.gross_revenue),0),
			COALESCE(SUM(v.gross_revenue - v.returns_amount),0),
			COALESCE(SUM(v.commission),0), COALESCE(SUM(v.logistics),0),
			COALESCE(SUM(v.cogs),0),
			COALESCE(SUM(
				v.for_pay - v.logistics - v.storage - v.acceptance
				- v.penalty - v.deduction + v.additional_payment
				+ v.reward_income - v.cogs),0)
			FROM v_pnl_daily v
			JOIN categories c ON c.id = v.category_id
			WHERE v.date >= $1 AND v.date <= $2 AND c.slug = $3`
		_ = h.db.QueryRow(ctx, pq, prevFrom, prevTo, catSlug).Scan(
			&prevGrossRev, &prevNetRev, &prevCommission, &prevLogi, &prevCogs, &prevNetProfit)
	}

	// --- Active SKUs + units sold (из v_pnl_daily) ---
	var activeSKUs int
	var unitsSold int64
	skuWhere := "WHERE v.date >= $1 AND v.date <= $2"
	skuArgs := []interface{}{dateFrom, dateTo}
	catJoin := ""
	if useDaily {
		catJoin = "JOIN categories c ON c.id = v.category_id"
		skuWhere += " AND c.slug = $3"
		skuArgs = append(skuArgs, catSlug)
	}
	skuQ := fmt.Sprintf(`SELECT
		COUNT(DISTINCT v.product_id) FILTER (WHERE v.units > 0),
		COALESCE(SUM(CASE WHEN v.units > 0 THEN v.units ELSE 0 END),0)
		FROM v_pnl_daily v %s %s`, catJoin, skuWhere)
	_ = h.db.QueryRow(ctx, skuQ, skuArgs...).Scan(&activeSKUs, &unitsSold)

	// --- Units returned (из wb_sales: supplier_oper_name='Возврат') ---
	var unitsReturned int64
	var retQ string
	var retArgs []interface{}
	if useDaily {
		retQ = `SELECT COALESCE(SUM(COALESCE(ws.quantity,1)),0)
			FROM wb_sales ws
			JOIN products p ON p.nm_id = ws.nm_id
			JOIN categories c ON c.id = p.category_id
			WHERE ws.sale_dt >= $1 AND ws.sale_dt <= $2
			  AND ws.supplier_oper_name = 'Возврат'
			  AND c.slug = $3`
		retArgs = []interface{}{dateFrom, dateTo, catSlug}
	} else {
		retQ = `SELECT COALESCE(SUM(COALESCE(ws.quantity,1)),0)
			FROM wb_sales ws
			WHERE ws.sale_dt >= $1 AND ws.sale_dt <= $2
			  AND ws.supplier_oper_name = 'Возврат'`
		retArgs = []interface{}{dateFrom, dateTo}
	}
	_ = h.db.QueryRow(ctx, retQ, retArgs...).Scan(&unitsReturned)

	// --- Daily breakdown ---
	var dailyQ string
	var dailyArgs []interface{}
	if !useDaily {
		dailyQ = `SELECT date,
			COALESCE(SUM(gross_revenue),0),  COALESCE(SUM(returns_amount),0),
			COALESCE(SUM(commission),0),     COALESCE(SUM(logistics),0),
			COALESCE(SUM(net_profit),0)
			FROM v_pnl_summary WHERE date >= $1 AND date <= $2
			GROUP BY date ORDER BY date`
		dailyArgs = []interface{}{dateFrom, dateTo}
	} else {
		dailyQ = `SELECT v.date,
			COALESCE(SUM(v.gross_revenue),0),  COALESCE(SUM(v.returns_amount),0),
			COALESCE(SUM(v.commission),0),     COALESCE(SUM(v.logistics),0),
			COALESCE(SUM(
				v.for_pay - v.logistics - v.storage - v.acceptance
				- v.penalty - v.deduction + v.additional_payment
				+ v.reward_income - v.cogs),0)
			FROM v_pnl_daily v
			JOIN categories c ON c.id = v.category_id
			WHERE v.date >= $1 AND v.date <= $2 AND c.slug = $3
			GROUP BY v.date ORDER BY v.date`
		dailyArgs = []interface{}{dateFrom, dateTo, catSlug}
	}
	dRows, _ := h.db.Query(ctx, dailyQ, dailyArgs...)
	var daily []gin.H
	if dRows != nil {
		defer dRows.Close()
		for dRows.Next() {
			var d time.Time
			var r, ret, cm, lg, pr float64
			if dRows.Scan(&d, &r, &ret, &cm, &lg, &pr) == nil {
				daily = append(daily, gin.H{
					"date": d.Format("2006-01-02"),
					"revenue": round2(r), "returns": round2(ret),
					"commission": round2(cm), "logistics": round2(lg),
					"profit": round2(pr),
				})
			}
		}
	}
	if daily == nil {
		daily = []gin.H{}
	}

	// --- By category ---
	cq := `SELECT COALESCE(c.name,'Без категории') AS cat_name,
		COALESCE(c.slug,'uncategorized') AS cat_slug,
		COALESCE(SUM(v.gross_revenue),0), COALESCE(SUM(v.commission),0),
		COALESCE(SUM(v.logistics),0),     COALESCE(SUM(v.cogs),0),
		COALESCE(SUM(
			v.for_pay - v.logistics - v.storage - v.acceptance
			- v.penalty - v.deduction + v.additional_payment
			+ v.reward_income - v.cogs),0) AS profit,
		COALESCE(SUM(CASE WHEN v.units > 0 THEN v.units ELSE 0 END),0) AS units
		FROM v_pnl_daily v
		LEFT JOIN categories c ON c.id = v.category_id
		WHERE v.date >= $1 AND v.date <= $2`
	cArgs := []interface{}{dateFrom, dateTo}
	if useDaily {
		cq += ` AND c.slug = $3`
		cArgs = append(cArgs, catSlug)
	}
	cq += ` GROUP BY c.name, c.slug ORDER BY SUM(v.gross_revenue) DESC NULLS LAST`

	cRows, _ := h.db.Query(ctx, cq, cArgs...)
	var byCat []gin.H
	if cRows != nil {
		defer cRows.Close()
		for cRows.Next() {
			var cn, cs string
			var cr, cc, cl, ccogs, cpr float64
			var cu int64
			if cRows.Scan(&cn, &cs, &cr, &cc, &cl, &ccogs, &cpr, &cu) == nil {
				byCat = append(byCat, gin.H{
					"category": cn, "slug": cs,
					"revenue": round2(cr), "commission": round2(cc),
					"logistics": round2(cl), "cogs": round2(ccogs),
					"profit": round2(cpr), "units": cu,
				})
			}
		}
	}
	if byCat == nil {
		byCat = []gin.H{}
	}

	h.pnlWBRespond(c, period,
		grossRev, returnsAmt, netRev, forPay,
		commission, logistics, acquiring, storage,
		penalty, deduction, acceptance, addpay,
		rewardIncome, cogs, netProfit,
		unitsSold, unitsReturned, activeSKUs,
		prevGrossRev, prevNetRev, prevCommission, prevLogi, prevCogs, prevNetProfit,
		daily, byCat)
}

func (h *Handler) pnlWBRespond(
	c *gin.Context, period string,
	grossRev, returnsAmt, netRev, forPay float64,
	commission, logistics, acquiring, storage float64,
	penalty, deduction, acceptance, addpay float64,
	rewardIncome, cogs, netProfit float64,
	unitsSold, unitsReturned int64, activeSKUs int,
	prevGrossRev, prevNetRev, prevCommission, prevLogi, prevCogs, prevNetProfit float64,
	daily, byCat []gin.H,
) {
	grossProfit := netRev - cogs
	operatingExpenses := commission + logistics + storage + acquiring + penalty + deduction + acceptance
	operatingProfit := netProfit
	calcNetProfit := netProfit

	returnRate := pct(float64(unitsReturned), float64(unitsSold+unitsReturned))
	avgCheck := div(grossRev, float64(unitsSold))
	avgProfitUnit := div(calcNetProfit, float64(unitsSold))

	grossMargin := pct(grossProfit, netRev)
	opMargin := pct(operatingProfit, netRev)
	netMargin := pct(calcNetProfit, netRev)

	var warnings []string
	if grossRev > 0 && pct(commission, grossRev) > 25 {
		warnings = append(warnings, fmt.Sprintf("Комиссия МП: %.1f%% от выручки — выше нормы", pct(commission, grossRev)))
	}
	if grossRev > 0 && pct(returnsAmt, grossRev) > 10 {
		warnings = append(warnings, fmt.Sprintf("Возвраты: %.1f%% от выручки", pct(returnsAmt, grossRev)))
	}
	if grossRev > 0 && pct(logistics, grossRev) > 15 {
		warnings = append(warnings, fmt.Sprintf("Логистика: %.1f%% от выручки", pct(logistics, grossRev)))
	}
	if calcNetProfit < 0 {
		warnings = append(warnings, "Бизнес убыточен за выбранный период!")
	}
	if warnings == nil {
		warnings = []string{}
	}
	prevGrossProfit := prevNetRev - prevCogs

	c.JSON(200, gin.H{
		"period": period,
		"source": "canonical_pnl_v1",
		"pnl": gin.H{
			"gross_revenue":      round2(grossRev),
			"returns_amount":     round2(returnsAmt),
			"net_revenue":        round2(netRev),
			"for_pay":            round2(forPay),
			"cogs":               round2(cogs),
			"gross_profit":       round2(grossProfit),
			"commission":         round2(commission),
			"logistics":          round2(logistics),
			"acquiring":          round2(acquiring),
			"storage":            round2(storage),
			"penalty":            round2(penalty),
			"deduction":          round2(deduction),
			"acceptance":         round2(acceptance),
			"return_logistics":   0.0,
			"additional_payment": round2(addpay),
			"reward_income":      round2(rewardIncome),
			"operating_expenses": round2(operatingExpenses),
			"operating_profit":   round2(operatingProfit),
			"advertising":        0.0,
			"net_profit":         round2(calcNetProfit),
		},
		"margins": gin.H{
			"gross_margin":     round2(grossMargin),
			"operating_margin": round2(opMargin),
			"net_margin":       round2(netMargin),
			"commission_pct":   round2(pct(commission, grossRev)),
			"logistics_pct":    round2(pct(logistics, grossRev)),
			"return_rate":      round2(returnRate),
		},
		"metrics": gin.H{
			"units_sold":          unitsSold,
			"units_returned":      unitsReturned,
			"active_skus":         activeSKUs,
			"avg_check":           round2(avgCheck),
			"avg_profit_per_unit": round2(avgProfitUnit),
		},
		"changes": gin.H{
			"gross_revenue":    changePctPtr(grossRev, prevGrossRev),
			"net_revenue":      changePctPtr(netRev, prevNetRev),
			"cogs":             changePctPtr(cogs, prevCogs),
			"gross_profit":     changePctPtr(grossProfit, prevGrossProfit),
			"commission":       changePctPtr(commission, prevCommission),
			"logistics":        changePctPtr(logistics, prevLogi),
			"operating_profit": changePctPtr(operatingProfit, prevNetProfit),
			"net_profit":       changePctPtr(calcNetProfit, prevNetProfit),
		},
		"changes_meta": gin.H{
			"prev_from":             "",
			"prev_to":               "",
			"prev_period_available": prevGrossRev > 0 || prevCogs > 0 || prevNetProfit != 0,
			"reason": func() string {
				if prevGrossRev == 0 && prevCogs == 0 && prevNetProfit == 0 {
					return "no_data_for_previous_period"
				}
				return ""
			}(),
		},
		"warnings":    warnings,
		"daily":       daily,
		"by_category": byCat,
	})
}

// ============================================================
// Legacy stub — для Ozon и прочих МП (пока canonical не готов)
// Возвращает пустую структуру с тем же контрактом, чтобы фронт не ломался.
// ============================================================
func (h *Handler) getPnLFullLegacy(
	c *gin.Context,
	period, dateFrom, dateTo, prevFrom, prevTo, catSlug, mpSlug string,
) {
	_ = dateFrom
	_ = dateTo
	_ = prevFrom
	_ = prevTo
	_ = catSlug

	c.JSON(200, gin.H{
		"period": period,
		"source": "legacy_not_migrated",
		"note":   fmt.Sprintf("Canonical P&L для marketplace=%s пока не реализован. Используйте /analytics/finance.", mpSlug),
		"pnl": gin.H{
			"gross_revenue": 0.0, "returns_amount": 0.0, "net_revenue": 0.0,
			"for_pay": 0.0, "cogs": 0.0, "gross_profit": 0.0,
			"commission": 0.0, "logistics": 0.0, "acquiring": 0.0, "storage": 0.0,
			"penalty": 0.0, "deduction": 0.0, "acceptance": 0.0,
			"return_logistics": 0.0, "additional_payment": 0.0, "reward_income": 0.0,
			"operating_expenses": 0.0, "operating_profit": 0.0,
			"advertising": 0.0, "net_profit": 0.0,
		},
		"margins": gin.H{
			"gross_margin": 0.0, "operating_margin": 0.0, "net_margin": 0.0,
			"commission_pct": 0.0, "logistics_pct": 0.0, "return_rate": 0.0,
		},
		"metrics": gin.H{
			"units_sold": 0, "units_returned": 0, "active_skus": 0,
			"avg_check": 0.0, "avg_profit_per_unit": 0.0,
		},
		"changes":     gin.H{},
		"warnings":    []string{},
		"daily":       []gin.H{},
		"by_category": []gin.H{},
	})
}
