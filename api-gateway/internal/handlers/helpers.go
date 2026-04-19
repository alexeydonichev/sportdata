package handlers

import (
	"context"
	"fmt"
	"math"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func round2(v float64) float64  { return math.Round(v*100) / 100 }

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

func changeDiff(current, previous float64) float64 { return round2(current - previous) }

// changePctPtr — как changePct, но при previous==0 возвращает nil
// (в JSON -> null). Используется где "нет базы сравнения" надо показать
// как "—", а не вводящие в заблуждение 100%.
func changePctPtr(current, previous float64) *float64 {
	if previous == 0 {
		return nil
	}
	v := round2((current - previous) / previous * 100)
	return &v
}


// pctChange — алиас для changePct (используется в returns.go)
func pctChange(current, previous float64) float64 { return changePct(current, previous) }

var (
	cachedMaxDate   time.Time
	maxDateMu       sync.Mutex
	maxDateCachedAt time.Time
)

func getMaxSaleDate(db *pgxpool.Pool) time.Time {
	maxDateMu.Lock()
	defer maxDateMu.Unlock()
	if !cachedMaxDate.IsZero() && time.Since(maxDateCachedAt) < 5*time.Minute {
		return cachedMaxDate
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var maxDate time.Time
	err := db.QueryRow(ctx,
		"SELECT COALESCE(MAX(sale_date), CURRENT_DATE) FROM sales").
		Scan(&maxDate)
	if err != nil || maxDate.IsZero() {
		maxDate = time.Now()
	}
	cachedMaxDate = maxDate
	maxDateCachedAt = time.Now()
	return cachedMaxDate
}

func periodRange(anchor time.Time, period string) (string, string) {
	to := anchor.Format("2006-01-02")
	switch period {
	case "today":
		return to, to
	case "yesterday":
		return anchor.AddDate(0, 0, -1).Format("2006-01-02"), anchor.AddDate(0, 0, -1).Format("2006-01-02")
	case "7d":
		return anchor.AddDate(0, 0, -7).Format("2006-01-02"), to
	case "14d":
		return anchor.AddDate(0, 0, -14).Format("2006-01-02"), to
	case "30d":
		return anchor.AddDate(0, 0, -30).Format("2006-01-02"), to
	case "90d":
		return anchor.AddDate(0, 0, -90).Format("2006-01-02"), to
	case "180d":
		return anchor.AddDate(0, 0, -180).Format("2006-01-02"), to
	case "365d", "1y":
		return anchor.AddDate(-1, 0, 0).Format("2006-01-02"), to
	default:
		return anchor.AddDate(0, 0, -7).Format("2006-01-02"), to
	}
}

func parsePeriod(period string) (string, string) {
	return periodRange(time.Now(), period)
}

func (h *Handler) parsePeriod(period string) (string, string) {
	return periodRange(getMaxSaleDate(h.db), period)
}

func prevPeriod(dateFrom, dateTo string) (string, string) {
	from, _ := time.Parse("2006-01-02", dateFrom)
	to, _ := time.Parse("2006-01-02", dateTo)
	duration := to.Sub(from)
	prevTo := from.AddDate(0, 0, -1)
	prevFrom := prevTo.Add(-duration)
	return prevFrom.Format("2006-01-02"), prevTo.Format("2006-01-02")
}

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

func buildSalesWherePrev(dateFrom, dateTo, category, marketplace string) (string, []interface{}) {
	return buildSalesWhere(dateFrom, dateTo, category, marketplace)
}


func parseDays(period string) int {
	switch period {
	case "today", "yesterday":
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
