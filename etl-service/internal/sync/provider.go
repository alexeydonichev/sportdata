package sync

import (
	"context"
	"time"

	"sportdata-etl/internal/models"
)

type Provider interface {
	Name() string
	MarketplaceSlug() string
	SyncSales(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error)
	SyncStocks(ctx context.Context, cred *models.Credential, apiKey string) (int, error)
}
