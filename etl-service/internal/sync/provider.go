package sync

import (
	"context"
	"time"

	"sportdata-etl/internal/models"
)

// Provider — базовый интерфейс для всех маркетплейсов
type Provider interface {
	Name() string
	MarketplaceSlug() string
	SyncSales(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error)
	SyncStocks(ctx context.Context, cred *models.Credential, apiKey string) (int, error)
}

// ReportProvider — расширенный интерфейс (WB Report Detail API)
// Если провайдер реализует этот интерфейс, engine использует SyncReport вместо SyncSales
type ReportProvider interface {
	SyncReport(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error)
}

// ReportDetailProvider — провайдер с поддержкой географии и возвратов
type ReportDetailProvider interface {
	SyncReportDetail(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error)
	SyncReturnsFromReport(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error)
}
