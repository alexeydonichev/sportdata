package handlers

import (
	"math"
	"testing"
	"time"
)

func TestRound2(t *testing.T) {
	tests := []struct {
		input, want float64
	}{
		{1.234, 1.23}, {1.235, 1.24}, {1.2, 1.2}, {0, 0},
		{-1.555, -1.56}, {100.999, 101}, {0.001, 0},
	}
	for _, tt := range tests {
		if got := round2(tt.input); got != tt.want {
			t.Errorf("round2(%v) = %v, want %v", tt.input, got, tt.want)
		}
	}
}

func TestPct(t *testing.T) {
	tests := []struct {
		part, total, want float64
	}{
		{50, 100, 50}, {1, 3, 33.33333333333333},
		{0, 100, 0}, {100, 0, 0}, {0, 0, 0}, {200, 100, 200},
	}
	for _, tt := range tests {
		if got := pct(tt.part, tt.total); math.Abs(got-tt.want) > 0.0001 {
			t.Errorf("pct(%v, %v) = %v, want %v", tt.part, tt.total, got, tt.want)
		}
	}
}

func TestDiv(t *testing.T) {
	tests := []struct {
		a, b, want float64
	}{
		{10, 2, 5}, {10, 0, 0}, {0, 0, 0}, {-10, 2, -5},
	}
	for _, tt := range tests {
		if got := div(tt.a, tt.b); math.Abs(got-tt.want) > 0.0001 {
			t.Errorf("div(%v, %v) = %v, want %v", tt.a, tt.b, got, tt.want)
		}
	}
}

func TestChangePct(t *testing.T) {
	tests := []struct {
		current, previous, want float64
	}{
		{110, 100, 10}, {100, 100, 0}, {50, 100, -50},
		{100, 0, 100}, {0, 0, 0}, {0, 100, -100}, {200, 50, 300},
	}
	for _, tt := range tests {
		if got := changePct(tt.current, tt.previous); got != tt.want {
			t.Errorf("changePct(%v, %v) = %v, want %v", tt.current, tt.previous, got, tt.want)
		}
	}
}

func TestChangeDiff(t *testing.T) {
	tests := []struct {
		current, previous, want float64
	}{
		{110, 100, 10}, {100, 100, 0}, {50, 100, -50},
		{0, 0, 0}, {100.555, 100.333, 0.22},
	}
	for _, tt := range tests {
		if got := changeDiff(tt.current, tt.previous); got != tt.want {
			t.Errorf("changeDiff(%v, %v) = %v, want %v", tt.current, tt.previous, got, tt.want)
		}
	}
}

func TestPctChangeAlias(t *testing.T) {
	if pctChange(110, 100) != changePct(110, 100) {
		t.Error("pctChange should delegate to changePct")
	}
}

func TestPeriodRange(t *testing.T) {
	anchor := time.Date(2025, 1, 15, 0, 0, 0, 0, time.UTC)
	tests := []struct {
		period, wantFrom, wantTo string
	}{
		{"today", "2025-01-15", "2025-01-15"},
		{"yesterday", "2025-01-14", "2025-01-14"},
		{"7d", "2025-01-08", "2025-01-15"},
		{"14d", "2025-01-01", "2025-01-15"},
		{"30d", "2024-12-16", "2025-01-15"},
		{"90d", "2024-10-17", "2025-01-15"},
		{"180d", "2024-07-19", "2025-01-15"},
		{"365d", "2024-01-15", "2025-01-15"},
		{"1y", "2024-01-15", "2025-01-15"},
		{"unknown", "2025-01-08", "2025-01-15"},
	}
	for _, tt := range tests {
		from, to := periodRange(anchor, tt.period)
		if from != tt.wantFrom || to != tt.wantTo {
			t.Errorf("periodRange(%s) = (%s,%s), want (%s,%s)",
				tt.period, from, to, tt.wantFrom, tt.wantTo)
		}
	}
}

func TestPrevPeriod(t *testing.T) {
	tests := []struct {
		dateFrom, dateTo, wantFrom, wantTo string
	}{
		{"2025-01-08", "2025-01-15", "2024-12-31", "2025-01-07"},
		{"2025-01-01", "2025-01-31", "2024-12-01", "2024-12-31"},
	}
	for _, tt := range tests {
		from, to := prevPeriod(tt.dateFrom, tt.dateTo)
		if from != tt.wantFrom || to != tt.wantTo {
			t.Errorf("prevPeriod(%s,%s) = (%s,%s), want (%s,%s)",
				tt.dateFrom, tt.dateTo, from, to, tt.wantFrom, tt.wantTo)
		}
	}
}

func TestBuildSalesWhere(t *testing.T) {
	_, args := buildSalesWhere("2025-01-01", "2025-01-31", "", "")
	if len(args) != 2 {
		t.Errorf("no filters: expected 2 args, got %d", len(args))
	}

	_, args = buildSalesWhere("2025-01-01", "2025-01-31", "shoes", "")
	if len(args) != 3 {
		t.Errorf("with category: expected 3 args, got %d", len(args))
	}

	_, args = buildSalesWhere("2025-01-01", "2025-01-31", "shoes", "ozon")
	if len(args) != 4 {
		t.Errorf("both filters: expected 4 args, got %d", len(args))
	}

	_, args = buildSalesWhere("2025-01-01", "2025-01-31", "all", "all")
	if len(args) != 2 {
		t.Errorf("'all' should be ignored: expected 2 args, got %d", len(args))
	}
}

func TestParseDays(t *testing.T) {
	tests := []struct {
		period string
		want   int
	}{
		{"today", 1}, {"yesterday", 1}, {"7d", 7}, {"14d", 14},
		{"30d", 30}, {"90d", 90}, {"180d", 180}, {"365d", 365},
		{"1y", 365}, {"unknown", 30},
	}
	for _, tt := range tests {
		if got := parseDays(tt.period); got != tt.want {
			t.Errorf("parseDays(%q) = %d, want %d", tt.period, got, tt.want)
		}
	}
}

func TestParsePeriodDays(t *testing.T) {
	tests := []struct {
		period string
		want   int
	}{
		{"7d", 7}, {"14d", 14}, {"90d", 90}, {"30d", 30}, {"unknown", 30},
	}
	for _, tt := range tests {
		if got := parseDays(tt.period); got != tt.want {
			t.Errorf("parseDays(%q) = %d, want %d", tt.period, got, tt.want)
		}
	}
}
