package ozon

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const baseURL = "https://api-seller.ozon.ru"

type Client struct {
	apiKey   string
	clientID string
	http     *http.Client
}

func NewClient(apiKey, clientID string) *Client {
	return &Client{
		apiKey:   apiKey,
		clientID: clientID,
		http:     &http.Client{Timeout: 60 * time.Second},
	}
}

func (c *Client) doPost(path string, body interface{}, result interface{}) error {
	jsonBody, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}

	req, err := http.NewRequest("POST", baseURL+path, bytes.NewReader(jsonBody))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Client-Id", c.clientID)
	req.Header.Set("Api-Key", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 429 {
		return fmt.Errorf("rate limited (429)")
	}
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		limit := len(b)
		if limit > 200 {
			limit = 200
		}
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(b[:limit]))
	}

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read body: %w", err)
	}
	return json.Unmarshal(respBody, result)
}

type TransactionListRequest struct {
	Filter   TransactionFilter `json:"filter"`
	Page     int64             `json:"page"`
	PageSize int64             `json:"page_size"`
}

type TransactionFilter struct {
	Date            TransactionDateFilter `json:"date"`
	TransactionType string                `json:"transaction_type,omitempty"`
}

type TransactionDateFilter struct {
	From string `json:"from"`
	To   string `json:"to"`
}

type TransactionListResponse struct {
	Result struct {
		Operations []Operation `json:"operations"`
		PageCount  int64       `json:"page_count"`
		RowCount   int64       `json:"row_count"`
	} `json:"result"`
}

type Operation struct {
	OperationID    int64            `json:"operation_id"`
	OperationType  string           `json:"operation_type"`
	OperationDate  string           `json:"operation_date"`
	Accruals       float64          `json:"accruals_for_sale"`
	SaleCommission float64          `json:"sale_commission"`
	DeliveryCharge float64          `json:"delivery_charge"`
	Items          []OperationItem  `json:"items"`
	Posting        OperationPosting `json:"posting"`
}

type OperationItem struct {
	Name string  `json:"name"`
	SKU  int64   `json:"sku"`
}

type OperationPosting struct {
	PostingNumber string `json:"posting_number"`
}

func (c *Client) GetTransactions(dateFrom, dateTo time.Time, page int64) (*TransactionListResponse, error) {
	req := TransactionListRequest{
		Filter: TransactionFilter{
			Date: TransactionDateFilter{
				From: dateFrom.Format("2006-01-02T00:00:00.000Z"),
				To:   dateTo.Format("2006-01-02T23:59:59.999Z"),
			},
		},
		Page:     page,
		PageSize: 1000,
	}
	var resp TransactionListResponse
	err := c.doPost("/v3/finance/transaction/list", req, &resp)
	return &resp, err
}

type StockRequest struct {
	Filter StockFilter `json:"filter,omitempty"`
	Limit  int64       `json:"limit"`
	LastID string      `json:"last_id,omitempty"`
}

type StockFilter struct {
	Visibility string `json:"visibility,omitempty"`
}

type StockResponse struct {
	Result struct {
		Items  []StockResultItem `json:"items"`
		LastID string            `json:"last_id"`
		Total  int64             `json:"total"`
	} `json:"result"`
}

type StockResultItem struct {
	ProductID int64       `json:"product_id"`
	OfferID   string      `json:"offer_id"`
	Stocks    []StockInfo `json:"stocks"`
}

type StockInfo struct {
	Type    string `json:"type"`
	Present int    `json:"present"`
}

func (c *Client) GetStocks(lastID string) (*StockResponse, error) {
	req := StockRequest{
		Filter: StockFilter{Visibility: "ALL"},
		Limit:  1000,
		LastID: lastID,
	}
	var resp StockResponse
	err := c.doPost("/v3/product/info/stocks", req, &resp)
	return &resp, err
}
