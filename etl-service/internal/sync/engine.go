package sync

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"sportdata-etl/internal/crypto"
	"sportdata-etl/internal/models"
)

const syncCooldown = 5 * time.Minute

type Engine struct {
	db            *pgxpool.Pool
	encryptionKey string
	providers     map[string]Provider
	mu            sync.Mutex
}

func NewEngine(db *pgxpool.Pool, encryptionKey string) *Engine {
	return &Engine{
		db:            db,
		encryptionKey: encryptionKey,
		providers:     make(map[string]Provider),
	}
}

func (e *Engine) RegisterProvider(p Provider) {
	e.providers[p.MarketplaceSlug()] = p
	log.Printf("[sync] registered provider: %s", p.Name())
}

func (e *Engine) RunAll(ctx context.Context) {
	creds, err := e.loadCredentials(ctx)
	if err != nil {
		log.Printf("[sync] load credentials error: %v", err)
		return
	}
	if len(creds) == 0 {
		log.Println("[sync] no active credentials found")
		return
	}
	for i := range creds {
		e.runCredential(ctx, &creds[i])
	}
}

func (e *Engine) RunBySlug(ctx context.Context, slug string) error {
	creds, err := e.loadCredentials(ctx)
	if err != nil {
		return fmt.Errorf("load credentials: %w", err)
	}
	found := false
	for i := range creds {
		if creds[i].MarketplaceSlug == slug {
			found = true
			e.runCredential(ctx, &creds[i])
		}
	}
	if !found {
		return fmt.Errorf("no active credentials for %s", slug)
	}
	return nil
}

func (e *Engine) RunByCredentialID(ctx context.Context, credID int) error {
	cred, err := e.loadCredentialByID(ctx, credID)
	if err != nil {
		return fmt.Errorf("credential %d: %w", credID, err)
	}
	e.runCredential(ctx, cred)
	return nil
}


func (e *Engine) RunBySlugWithOpts(ctx context.Context, slug string, opts *SyncOptions) error {
	creds, err := e.loadCredentials(ctx)
	if err != nil {
		return fmt.Errorf("load credentials: %w", err)
	}
	found := false
	for i := range creds {
		if creds[i].MarketplaceSlug == slug {
			found = true
			e.runCredentialWithOpts(ctx, &creds[i], opts)
		}
	}
	if !found {
		return fmt.Errorf("no active credentials for %s", slug)
	}
	return nil
}

func (e *Engine) RunByCredentialIDWithOpts(ctx context.Context, credID int, opts *SyncOptions) error {
	cred, err := e.loadCredentialByID(ctx, credID)
	if err != nil {
		return fmt.Errorf("credential %d: %w", credID, err)
	}
	e.runCredentialWithOpts(ctx, cred, opts)
	return nil
}

func (e *Engine) runCredential(ctx context.Context, cred *models.Credential) {
	e.runCredentialWithOpts(ctx, cred, nil)
}

func (e *Engine) runCredentialWithOpts(ctx context.Context, cred *models.Credential, opts *SyncOptions) {
	e.mu.Lock()
	defer e.mu.Unlock()

	// Rate-limit только для авто-запусков (opts == nil)
	if opts == nil && cred.LastSyncAt != nil && time.Since(*cred.LastSyncAt) < syncCooldown {
		remaining := syncCooldown - time.Since(*cred.LastSyncAt)
		log.Printf("[sync] %s (cred #%d) rate limited, retry in %v",
			cred.MarketplaceSlug, cred.ID, remaining.Round(time.Second))
		return
	}

	provider, ok := e.providers[cred.MarketplaceSlug]
	if !ok {
		log.Printf("[sync] no provider for %s", cred.MarketplaceSlug)
		return
	}

	apiKey, err := crypto.Decrypt(cred.APIKeyEncrypted, e.encryptionKey)
	if err != nil {
		log.Printf("[sync] decrypt key for cred #%d failed: %v", cred.ID, err)
		e.createFailedJob(ctx, cred, "full_sync", fmt.Sprintf("decrypt error: %v", err))
		return
	}

	log.Printf("[sync] starting %s (cred #%d: %s) opts=%+v",
		cred.MarketplaceSlug, cred.ID, cred.Name, opts)

	dateTo := time.Now()
	dateFrom := dateTo.AddDate(0, 0, -90)
	if opts != nil {
		if opts.DateFrom != nil {
			dateFrom = *opts.DateFrom
		}
		if opts.DateTo != nil {
			dateTo = *opts.DateTo
		}
	}

	// Основная синхронизация продаж
	e.runJob(ctx, cred, "sales", func(ctx context.Context) (int, error) {
		if pwo, ok := provider.(ProviderWithOptions); ok {
			return pwo.SyncSalesWithOptions(ctx, cred, apiKey, dateFrom, dateTo, opts)
		}
		if rp, ok := provider.(ReportProvider); ok {
			return rp.SyncReport(ctx, cred, apiKey, dateFrom, dateTo)
		}
		return provider.SyncSales(ctx, cred, apiKey, dateFrom, dateTo)
	})

	// Синхронизация остатков
	e.runJob(ctx, cred, "stocks", func(ctx context.Context) (int, error) {
		return provider.SyncStocks(ctx, cred, apiKey)
	})

	e.db.Exec(ctx,
		"UPDATE marketplace_credentials SET last_sync_at=NOW() WHERE id=$1",
		cred.ID)
}

func (e *Engine) runJob(ctx context.Context, cred *models.Credential, jobType string, fn func(ctx context.Context) (int, error)) {
	now := time.Now()
	var jobID int64
	err := e.db.QueryRow(ctx,
		`INSERT INTO sync_jobs (marketplace_id, credential_id, job_type, status, started_at, created_at)
		 VALUES ($1, $2, $3, 'running', $4, $4) RETURNING id`,
		cred.MarketplaceID, cred.ID, jobType, now,
	).Scan(&jobID)
	if err != nil {
		log.Printf("[sync] failed to create job: %v", err)
		return
	}

	log.Printf("[sync] job #%d: %s/%s started", jobID, cred.MarketplaceSlug, jobType)

	records, err := fn(ctx)
	completed := time.Now()

	if err != nil {
		log.Printf("[sync] job #%d failed: %v", jobID, err)
		e.db.Exec(ctx,
			`UPDATE sync_jobs SET status='failed', completed_at=$1, error_message=$2, records_processed=$3 WHERE id=$4`,
			completed, err.Error(), records, jobID)
		return
	}

	log.Printf("[sync] job #%d: %d records in %v",
		jobID, records, completed.Sub(now).Round(time.Millisecond))
	e.db.Exec(ctx,
		`UPDATE sync_jobs SET status='completed', completed_at=$1, records_processed=$2 WHERE id=$3`,
		completed, records, jobID)
}

func (e *Engine) createFailedJob(ctx context.Context, cred *models.Credential, jobType, errMsg string) {
	now := time.Now()
	e.db.Exec(ctx,
		`INSERT INTO sync_jobs (marketplace_id, credential_id, job_type, status, started_at, completed_at, error_message, created_at)
		 VALUES ($1, $2, $3, 'failed', $4, $4, $5, $4)`,
		cred.MarketplaceID, cred.ID, jobType, now, errMsg)
}

func (e *Engine) loadCredentials(ctx context.Context) ([]models.Credential, error) {
	rows, err := e.db.Query(ctx, `
		SELECT mc.id, mc.marketplace_id, m.slug, mc.name, mc.api_key_encrypted,
		       COALESCE(mc.client_id,''), mc.is_active, mc.last_sync_at
		FROM marketplace_credentials mc
		JOIN marketplaces m ON m.id = mc.marketplace_id
		WHERE mc.is_active = true
		ORDER BY mc.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []models.Credential
	for rows.Next() {
		var c models.Credential
		if err := rows.Scan(&c.ID, &c.MarketplaceID, &c.MarketplaceSlug,
			&c.Name, &c.APIKeyEncrypted, &c.ClientID, &c.IsActive, &c.LastSyncAt); err != nil {
			return nil, err
		}
		result = append(result, c)
	}
	return result, nil
}

func (e *Engine) loadCredentialByID(ctx context.Context, id int) (*models.Credential, error) {
	var c models.Credential
	err := e.db.QueryRow(ctx, `
		SELECT mc.id, mc.marketplace_id, m.slug, mc.name, mc.api_key_encrypted,
		       COALESCE(mc.client_id,''), mc.is_active, mc.last_sync_at
		FROM marketplace_credentials mc
		JOIN marketplaces m ON m.id = mc.marketplace_id
		WHERE mc.id=$1 AND mc.is_active=true`, id,
	).Scan(&c.ID, &c.MarketplaceID, &c.MarketplaceSlug,
		&c.Name, &c.APIKeyEncrypted, &c.ClientID, &c.IsActive, &c.LastSyncAt)
	if err != nil {
		return nil, err
	}
	return &c, nil
}
