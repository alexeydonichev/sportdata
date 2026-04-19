package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"sportdata-etl/internal/sync"
)

type Handler struct {
	engine    *sync.Engine
	etlSecret string
}

func NewHandler(engine *sync.Engine, etlSecret string) *Handler {
	return &Handler{engine: engine, etlSecret: etlSecret}
}

func (h *Handler) SetupRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/health", h.health)
	mux.HandleFunc("/api/trigger", h.authMiddleware(h.trigger))
}

func (h *Handler) authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		secret := r.Header.Get("X-ETL-Secret")
		if h.etlSecret == "" || secret != h.etlSecret {
			log.Printf("[api] unauthorized trigger attempt from %s", r.RemoteAddr)
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

type TriggerRequest struct {
	Marketplace  string `json:"marketplace"`
	CredentialID int    `json:"credential_id"`
	DateFrom     string `json:"date_from"`  // YYYY-MM-DD (optional)
	DateTo       string `json:"date_to"`    // YYYY-MM-DD (optional)
	ForceFull    bool   `json:"force_full"` // skip incremental narrowing
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "etl-worker"})
}

func (h *Handler) trigger(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req TriggerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid json"}`, http.StatusBadRequest)
		return
	}

	opts := &sync.SyncOptions{ForceFull: req.ForceFull}
	if req.DateFrom != "" {
		if t, err := time.Parse("2006-01-02", req.DateFrom); err == nil {
			opts.DateFrom = &t
		} else {
			http.Error(w, `{"error":"invalid date_from, expected YYYY-MM-DD"}`, http.StatusBadRequest)
			return
		}
	}
	if req.DateTo != "" {
		if t, err := time.Parse("2006-01-02", req.DateTo); err == nil {
			// включаем весь день до 23:59:59
			t = t.Add(24*time.Hour - time.Second)
			opts.DateTo = &t
		} else {
			http.Error(w, `{"error":"invalid date_to, expected YYYY-MM-DD"}`, http.StatusBadRequest)
			return
		}
	}

	go func(opts *sync.SyncOptions) {
		ctx := context.Background()
		if req.CredentialID > 0 {
			if err := h.engine.RunByCredentialIDWithOpts(ctx, req.CredentialID, opts); err != nil {
				log.Printf("[api] trigger cred #%d error: %v", req.CredentialID, err)
			}
		} else if req.Marketplace != "" {
			if err := h.engine.RunBySlugWithOpts(ctx, req.Marketplace, opts); err != nil {
				log.Printf("[api] trigger %s error: %v", req.Marketplace, err)
			}
		} else {
			h.engine.RunAll(ctx)
		}
	}(opts)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "queued", "message": "sync triggered"})
}
