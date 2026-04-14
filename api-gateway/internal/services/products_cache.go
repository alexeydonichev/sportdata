package services

import (
	"encoding/json"
	"time"

	"sportdata/api-gateway/internal/cache"

	"github.com/redis/go-redis/v9"
)

const ProductsCacheKey = "products:list"

func GetProductsCached(rdb *redis.Client, fetch func() (any, error)) (any, error) {

	data, err := cache.Get(rdb, ProductsCacheKey)

	if err == nil {
		var result any
		if json.Unmarshal(data, &result) == nil {
			return result, nil
		}
	}

	result, err := fetch()
	if err != nil {
		return nil, err
	}

	bytes, _ := json.Marshal(result)

	rdb.Set(cache.Ctx, ProductsCacheKey, bytes, 60*time.Second)

	return result, nil
}
