package handlers

import (
	"context"
	"fmt"
	"math"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// ── Математика ───────────────────────────────────────────────────────

func round2(v float64) float64 {
	return math.Round(v*100) / 100
}

func pct(part, total float64) float64 {
	if total == 0 {
		return 0
	}
	return part / total * 100
}

func div(a, b float64) float64 {
	if b == 0 {
		return 0
	}
	return a / b
}

func changePct(current, previous float64) float64 {
	if previous == 0 {
		if current > 0 {
			return 100
		}
		return 0
	}
	return round2((current - previous) / previous * 100)
}

func changeDiff(current, previous float64) float64 {
	return round2(current - previous)
}

// ── Период ───────────────────────────────────────────────────────────

func parsePeriod(period string) (string, string) {
	now := time.Now()
	dateTo := now.Format("2006-01-02")

	switch period {
	case "today":
		return dateTo, dateTo
	case "yesterday":
		y := now.AddDate(0, 0, -1).Format("2006-01-02")
		return y, y
	case "7d":
		return now.AddDate(0, 0, -7).Format("2006-01-02"), dateTo
	case "14d":
		return now.AddDate(0, 0, -14).Format("2006-01-02"), dateTo
	case "30d":
		return now.AddDate(0, 0, -30).Format("2006-01-02"), dateTo
	case "90d":
		return now.AddDate(0, 0, -90).Format("2006-01-02"), dateTo
	case "180d":
		return now.AddDate(0, 0, -180).Format("2006-01-02"), dateTo
	case "365d", "1y":
		return now.AddDate(-1, 0, 0).Format("2006-01-02"), dateTo
	default:
		return now.AddDate(0, 0, -7).Format("2006-01-02"), dateTo
	}
}

func prevPeriod(dateFrom, dateTo string) (string, string) {
	from, _ := time.Parse("2006-01-02", dateFrom)
	to, _ := time.Parse("2006-01-02", dateTo)
	duration := to.Sub(from)
	prevTo := from.AddDate(0, 0, -1)
	prevFrom := prevTo.Add(-duration)
	return prevFrom.Format("2006-01-02"), prevTo.Format("2006-01-02")
}

// ── Фильтры SQL ─────────────────────────────────────────────────────

func buildSalesWhere(dateFrom, dateTo, category, marketplace string) (string, []interface{}) {
	where := " WHERE s.sale_date >= $1 AND s.sale_date <= $2"
	args := []interface{}{dateFrom, dateTo}
	idx := 3

	if category != "" && category != "all" {
		where += fmt.Sprintf(" AND c.slug = $%d", idx)
		args = append(args, category)
		idx++
	}
	if marketplace != "" && marketplace != "all" {
		where += fmt.Sprintf(" AND m.slug = $%d", idx)
		args = append(args, marketplace)
	}
	return where, args
}

// buildSalesWherePrev — алиас, оставлен для читаемости вызывающего кода.
func buildSalesWherePrev(dateFrom, dateTo, category, marketplace string) (string, []interface{}) {
	return buildSalesWhere(dateFrom, dateTo, category, marketplace)
}

// ── Health Check ─────────────────────────────────────────────────────

func (h *Handler) HealthCheck(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	dbOK := h.db.Ping(ctx) == nil
	status := "ok"
	code := http.StatusOK
	if !dbOK {
		status = "degraded"
		code = http.StatusServiceUnavailable
	}

	c.JSON(code, gin.H{
		"status":   status,
		"postgres": dbOK,
		"time":     time.Now().Format(time.RFC3339),
		"version":  "2.0.0",
	})
}

// ── Дополнительные утилиты ───────────────────────────────────────────

// parseDays извлекает количество дней из строки периода ("7d" → 7, "30d" → 30 и т.д.)
func parseDays(period string) int {
	switch period {
	case "today":
		return 1
	case "yesterday":
		return 1
	case "7d":
		return 7
	case "14d":
		return 14
	case "30d":
		return 30
	case "90d":
		return 90
	case "180d":
		return 180
	case "365d", "1y":
		return 365
	default:
		return 30
	}
}

// pctChange — процентное изменение от previous к current
func pctChange(current, previous float64) float64 {
	if previous == 0 {
		if current > 0 {
			return 100
		}
		return 0
	}
	return round2((current - previous) / previous * 100)
}
