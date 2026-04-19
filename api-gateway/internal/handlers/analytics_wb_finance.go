package handlers

import (
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

// GetFinanceWB возвращает финансовый отчёт по Wildberries из view v_wb_income_expenses_daily.
// Формулы соответствуют ЛК WB 1-в-1. Формат ответа совместим с FinanceResponse на фронте.
func (h *Handler) GetFinanceWB(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := h.parsePeriod(period)
	fmt.Printf("[FINANCE_WB_DEBUG] period=%s dateFrom=%s dateTo=%s\n", period, dateFrom, dateTo)
	prevFrom, prevTo := prevPeriod(dateFrom, dateTo)

	// --- 1. Суммарные метрики за период ---
	var (
		salesRevenue, logistics, storage, acceptance, penalty float64
		addpay, deduction, defects, wbCommission, forPay, grandTotal float64
		salesQty int64
	)

	q := `SELECT
		COALESCE(SUM(sales_revenue), 0),
		COALESCE(SUM(sales_qty),     0),
		COALESCE(SUM(logistics),     0),
		COALESCE(SUM(storage),       0),
		COALESCE(SUM(acceptance),    0),
		COALESCE(SUM(penalty),       0),
		COALESCE(SUM(addpay),        0),
		COALESCE(SUM(deduction),     0),
		COALESCE(SUM(defects),       0),
		COALESCE(SUM(wb_commission), 0),
		COALESCE(SUM(for_pay),       0),
		COALESCE(SUM(grand_total),   0)
		FROM v_wb_income_expenses_daily
		WHERE sale_dt >= $1 AND sale_dt <= $2`

	if err := h.db.QueryRow(ctx, q, dateFrom, dateTo).Scan(
		&salesRevenue, &salesQty, &logistics, &storage, &acceptance, &penalty,
		&addpay, &deduction, &defects, &wbCommission, &forPay, &grandTotal,
	); err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}

	// --- 2. Прошлый период для changes ---
	var prevRevenue, prevCommission, prevLogistics, prevGrandTotal float64
	pq := `SELECT
		COALESCE(SUM(sales_revenue), 0),
		COALESCE(SUM(wb_commission), 0),
		COALESCE(SUM(logistics),     0),
		COALESCE(SUM(grand_total),   0)
		FROM v_wb_income_expenses_daily
		WHERE sale_dt >= $1 AND sale_dt <= $2`
	_ = h.db.QueryRow(ctx, pq, prevFrom, prevTo).Scan(
		&prevRevenue, &prevCommission, &prevLogistics, &prevGrandTotal,
	)

	// --- 3. Разбивка по неделям ---
	wq := `SELECT date_trunc('week', sale_dt)::date AS wk,
		COALESCE(SUM(sales_revenue), 0),
		COALESCE(SUM(for_pay),       0),
		COALESCE(SUM(wb_commission), 0),
		COALESCE(SUM(logistics),     0),
		COALESCE(SUM(storage),       0),
		COALESCE(SUM(penalty),       0),
		COALESCE(SUM(grand_total),   0)
		FROM v_wb_income_expenses_daily
		WHERE sale_dt >= $1 AND sale_dt <= $2
		GROUP BY wk
		ORDER BY wk`
	wRows, _ := h.db.Query(ctx, wq, dateFrom, dateTo)
	weekly := []gin.H{}
	if wRows != nil {
		defer wRows.Close()
		for wRows.Next() {
			var wk time.Time
			var wr, wp, wc, wl, ws, wpen, wpr float64
			if wRows.Scan(&wk, &wr, &wp, &wc, &wl, &ws, &wpen, &wpr) == nil {
				weekly = append(weekly, gin.H{
					"week":       wk.Format("2006-01-02"),
					"revenue":    round2(wr),
					"for_pay":    round2(wp),
					"commission": round2(wc),
					"logistics":  round2(wl),
					"storage":    round2(ws),
					"penalty":    round2(wpen),
					"net_profit": round2(wpr),
				})
			}
		}
	}

	// --- 4. Warnings ---
	warnings := []string{}
	if salesRevenue > 0 && pct(wbCommission, salesRevenue) > 25 {
		warnings = append(warnings, fmt.Sprintf("Комиссия WB: %.1f%% — выше нормы", pct(wbCommission, salesRevenue)))
	}
	if salesRevenue > 0 && pct(logistics, salesRevenue) > 15 {
		warnings = append(warnings, fmt.Sprintf("Логистика: %.1f%% от выручки", pct(logistics, salesRevenue)))
	}
	if salesRevenue > 0 && pct(storage, salesRevenue) > 5 {
		warnings = append(warnings, fmt.Sprintf("Хранение: %.1f%% от выручки", pct(storage, salesRevenue)))
	}
	if penalty > 0 {
		warnings = append(warnings, fmt.Sprintf("Штрафы: %.0f ₽", penalty))
	}
	if deduction > 10000 {
		warnings = append(warnings, fmt.Sprintf("Удержания: %.0f ₽", deduction))
	}
	if grandTotal < 0 {
		warnings = append(warnings, "Итого к выплате < 0 — убыточный период")
	}

	// --- 5. JSON в формате, совместимом с FinanceResponse ---
	c.JSON(200, gin.H{
		"period": period,
		"source": "wb_finrep_v2",
		"pnl": gin.H{
			"gross_revenue":      round2(salesRevenue), // = sales_revenue из view
			"returns_amount":     0.0,                  // уже вычтены внутри sales_revenue
			"net_revenue":        round2(salesRevenue),
			"for_pay":            round2(forPay),
			"commission":         round2(wbCommission),
			"logistics":          round2(logistics),
			"acquiring":          0.0, // WB не выделяет
			"storage":            round2(storage),
			"penalty":            round2(penalty),
			"deduction":          round2(deduction),
			"acceptance":         round2(acceptance),
			"return_logistics":   0.0,
			"additional_payment": round2(addpay),
			"defects":            round2(defects),
			"cogs":               0.0, // COGS пока не считаем из view
			"net_profit":         round2(grandTotal), // = grand_total (к выплате)
		},
		"margins": gin.H{
			"gross_margin":   round2(pct(grandTotal, salesRevenue)),
			"net_margin":     round2(pct(grandTotal, salesRevenue)),
			"commission_pct": round2(pct(wbCommission, salesRevenue)),
			"logistics_pct":  round2(pct(logistics, salesRevenue)),
			"return_rate":    0.0,
		},
		"changes": gin.H{
			"gross_revenue": changePct(salesRevenue, prevRevenue),
			"commission":    changePct(wbCommission, prevCommission),
			"logistics":     changePct(logistics, prevLogistics),
			"net_profit":    changePct(grandTotal, prevGrandTotal),
		},
		"weekly":      weekly,
		"by_category": []gin.H{}, // TODO: по категориям через join с products (если понадобится)
		"warnings":    warnings,
		"metrics": gin.H{
			"units_sold": salesQty,
		},
	})
}
