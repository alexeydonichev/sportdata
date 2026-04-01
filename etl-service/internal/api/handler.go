package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

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

	go func() {
		ctx := context.Background()
		if req.CredentialID > 0 {
			if err := h.engine.RunByCredentialID(ctx, req.CredentialID); err != nil {
				log.Printf("[api] trigger cred #%d error: %v", req.CredentialID, err)
			}
		} else if req.Marketplace != "" {
			if err := h.engine.RunBySlug(ctx, req.Marketplace); err != nil {
				log.Printf("[api] trigger %s error: %v", req.Marketplace, err)
			}
		} else {
			h.engine.RunAll(ctx)
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "queued", "message": "sync triggered"})
}
