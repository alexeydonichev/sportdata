package main

import (
	"log"
	"net/http"
)

func trigger(w http.ResponseWriter, r *http.Request) {
	log.Println("SYNC TRIGGERED")
	w.Write([]byte(`{"status":"ok"}`))
}

func main() {
	http.HandleFunc("/api/trigger", trigger)

	log.Println("ETL mock running :8081")
	log.Fatal(http.ListenAndServe(":8081", nil))
}
