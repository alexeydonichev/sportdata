package models

import "time"

type Credential struct {
	ID              int
	MarketplaceID   int
	MarketplaceSlug string
	Name            string
	APIKeyEncrypted string
	ClientID        string
	IsActive        bool
	LastSyncAt      *time.Time
}
