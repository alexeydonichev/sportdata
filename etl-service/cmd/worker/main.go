package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"sportdata-etl/internal/api"
	"sportdata-etl/internal/config"
	"sportdata-etl/internal/db"
	"sportdata-etl/internal/marketplace/ozon"
	"sportdata-etl/internal/marketplace/wildberries"
	"sportdata-etl/internal/sync"
)

func main() {
	log.Println("YourFit ETL Worker starting...")

	cfg := config.Load()
	if cfg.EncryptionKey == "" {
		log.Fatal("ENCRYPTION_KEY is required")
	}

	pool, err := db.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("PostgreSQL error: %v", err)
	}
	defer pool.Close()
	log.Println("PostgreSQL connected")

	engine := sync.NewEngine(pool, cfg.EncryptionKey)
	engine.RegisterProvider(wildberries.NewProvider(pool))
	engine.RegisterProvider(ozon.NewProvider(pool))

	handler := api.NewHandler(engine, cfg.ETLSecret)
	mux := http.NewServeMux()
	handler.SetupRoutes(mux)

	server := &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
	}

	go func() {
		log.Printf("ETL HTTP API listening on %s", cfg.ListenAddr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server error: %v", err)
		}
	}()

	interval, err := time.ParseDuration(cfg.WorkerInterval)
	if err != nil {
		interval = 30 * time.Minute
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	log.Printf("Scheduled sync every %v", interval)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	for {
		select {
		case <-ticker.C:
			log.Println("Running scheduled sync...")
			engine.RunAll(ctx)
		case <-quit:
			log.Println("Shutting down...")
			cancel()
			server.Shutdown(context.Background())
			return
		}
	}
}
