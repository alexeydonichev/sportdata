#!/bin/bash

BASE_URL="${BASE_URL:-http://localhost:3000}"
PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf "  \033[0;32mPASS\033[0m %s (%s)\n" "$name" "$actual"
    ((PASS++))
  else
    printf "  \033[0;31mFAIL\033[0m %s (want %s got %s)\n" "$name" "$expected" "$actual"
    ((FAIL++))
  fi
}

printf "\n\033[1;33m=== SportData API Tests ===\033[0m\n\n"

# ---- [1] AUTH ----
printf "\033[1;33m[1/4] AUTH\033[0m\n"

LOGIN_JSON=$(python3 -c "import json,os; print(json.dumps({'email':os.environ['SUPERADMIN_EMAIL'],'password':os.environ['SUPERADMIN_PASSWORD']}))")

CODE=$(curl -s -o /tmp/sd_login -w '%{http_code}' -X POST "$BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" -d "$LOGIN_JSON")
check "Login success" "200" "$CODE"
TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/sd_login')).get('token',''))" 2>/dev/null)

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" -d '{"email":"x@x.x","password":"wrong"}')
check "Login wrong password" "401" "$CODE"

CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/dashboard")
check "No auth header" "401" "$CODE"

CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/dashboard" \
  -H "Authorization: Bearer invalidtoken")
check "Invalid token" "401" "$CODE"

# ---- [2] API ENDPOINTS ----
printf "\n\033[1;33m[2/4] API ENDPOINTS\033[0m\n"

ENDPOINTS=(
  "dashboard"
  "analytics/finance?period=7d"
  "analytics/finance?period=30d"
  "analytics/finance?period=90d"
  "analytics/returns?period=30d"
  "analytics/geography"
  "analytics/unit-economics?period=30d"
  "products"
  "products/categories"
  "sync/status"
  "sync/history"
)

for ep in "${ENDPOINTS[@]}"; do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/$ep" \
    -H "Authorization: Bearer $TOKEN")
  check "GET /api/v1/$ep" "200" "$CODE"
done

# ---- [3] DATA VALIDATION ----
printf "\n\033[1;33m[3/4] DATA VALIDATION\033[0m\n"

VALIDATION=$(python3 << PYVAL
import urllib.request, json, sys

token = "${TOKEN}"
base = "${BASE_URL}"
hdr = {"Authorization": f"Bearer {token}"}
ok = 0
fail = 0

def get(path):
    req = urllib.request.Request(f"{base}/api/v1/{path}", headers=hdr)
    return json.loads(urllib.request.urlopen(req).read())

def test(name, condition):
    global ok, fail
    if condition:
        print(f"  \033[0;32mPASS\033[0m {name}")
        ok += 1
    else:
        print(f"  \033[0;31mFAIL\033[0m {name}")
        fail += 1

try:
    d = get("dashboard")
    test("Dashboard: revenue > 0", float(d["total_revenue"]) > 0)
    test("Dashboard: orders > 0", int(d["total_orders"]) > 0)
    test("Dashboard: has marketplaces", len(d.get("by_marketplace", [])) > 0)
    test("Dashboard: has top_products", len(d.get("top_products", [])) > 0)
    test("Dashboard: has changes", "changes" in d)

    d = get("analytics/finance?period=30d")
    test("Finance: has pnl.gross_revenue", "gross_revenue" in d.get("pnl", {}))
    test("Finance: has weekly data", len(d.get("weekly", [])) > 0)
    test("Finance: has by_category", len(d.get("by_category", [])) > 0)
    test("Finance: has margins", "gross_margin" in d.get("margins", {}))

    d = get("analytics/returns?period=30d")
    test("Returns: has return_rate", "return_rate" in d.get("summary", {}))
    test("Returns: valid rate 0-100", 0 <= float(d["summary"]["return_rate"]) <= 100)
    test("Returns: has daily data", len(d.get("daily", [])) > 0)
    test("Returns: has by_product", len(d.get("by_product", [])) > 0)

    d = get("analytics/geography")
    test("Geography: has marketplaces", len(d.get("by_marketplace", [])) > 0)
    test("Geography: has summary", "total_revenue" in d.get("summary", {}))

    d = get("analytics/unit-economics?period=30d")
    test("Unit-econ: has items", len(d.get("items", [])) > 0)
    test("Unit-econ: has summary", "total_revenue" in d.get("summary", {}))

    products = get("products")
    test("Products: count >= 10", len(products) >= 10)
    test("Products: has name+sku", "name" in products[0] and "sku" in products[0])

    cats = get("products/categories")
    test("Categories: count >= 1", len(cats) >= 1)
    test("Categories: has name+slug", "name" in cats[0] and "slug" in cats[0])

    pid = products[0]["id"]
    single = get(f"products/{pid}")
    test(f"Product #{pid}: has details", "name" in single)

    d = get("sync/status")
    test("Sync status: has stats", "stats" in d)

    d = get("sync/history")
    test("Sync history: is array", isinstance(d, list))

except Exception as e:
    print(f"  \033[0;31mERROR\033[0m {e}")
    fail += 1

print(f"VALIDATION_RESULT:{ok}:{fail}")
PYVAL
)

echo "$VALIDATION" | grep -v "^VALIDATION_RESULT:"
V_OK=$(echo "$VALIDATION" | grep "^VALIDATION_RESULT:" | cut -d: -f2)
V_FAIL=$(echo "$VALIDATION" | grep "^VALIDATION_RESULT:" | cut -d: -f3)
((PASS+=V_OK))
((FAIL+=V_FAIL))

# ---- [4] FRONTEND PAGES ----
printf "\n\033[1;33m[4/4] FRONTEND PAGES\033[0m\n"

PAGES=(
  "/"
  "/analytics/finance"
  "/analytics/returns"
  "/analytics/geography"
  "/analytics/unit-economics"
  "/products"
  "/sync"
  "/sales"
  "/settings"
)

for pg in "${PAGES[@]}"; do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL$pg")
  check "GET $pg" "200" "$CODE"
done

# ---- SUMMARY ----
TOTAL=$((PASS + FAIL))
printf "\n\033[1;33m══════════════════════════════════════\033[0m\n"
printf "  Total: %d | \033[0;32mPassed: %d\033[0m | \033[0;31mFailed: %d\033[0m\n" "$TOTAL" "$PASS" "$FAIL"

if [ "$FAIL" -eq 0 ]; then
  printf "\n  \033[0;32m✅ ALL TESTS PASSED!\033[0m\n\n"
  exit 0
else
  printf "\n  \033[0;31m❌ SOME TESTS FAILED\033[0m\n\n"
  exit 1
fi
