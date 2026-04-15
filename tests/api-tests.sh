#!/bin/bash
set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
PASS=0; FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf "  \033[32mPASS\033[0m %s (%s)\n" "$name" "$actual"; ((PASS++))
  else
    printf "  \033[31mFAIL\033[0m %s (want %s got %s)\n" "$name" "$expected" "$actual"; ((FAIL++))
  fi
}

printf "\n\033[1;33m=== SportData API Tests ===\033[0m\n\n"

# ── [1] HEALTH ──
printf "\033[1;33m[1/5] HEALTH\033[0m\n"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/health")
check "GET /health" "200" "$CODE"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/health")
check "GET /api/v1/health" "200" "$CODE"

# ── [2] AUTH ──
printf "\n\033[1;33m[2/5] AUTH\033[0m\n"
SA_EMAIL="${SUPERADMIN_EMAIL:-}"
SA_PASS="${SUPERADMIN_PASSWORD:-}"
if [ -z "$SA_EMAIL" ] || [ -z "$SA_PASS" ]; then
  echo "  SKIP — SUPERADMIN_EMAIL/PASSWORD not set"
else
  LOGIN_JSON="{\"email\":\"$SA_EMAIL\",\"password\":\"$SA_PASS\"}"
  CODE=$(curl -s -o /tmp/sd_login -w '%{http_code}' -X POST "$BASE_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" -d "$LOGIN_JSON")
  check "Login success" "200" "$CODE"
  TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/sd_login')).get('token',''))" 2>/dev/null || echo "")

  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" -d '{"email":"x@x.x","password":"wrongpassword1"}')
  check "Login wrong password" "401" "$CODE"

  CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/dashboard")
  check "No auth header" "401" "$CODE"

  CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/dashboard" \
    -H "Authorization: Bearer invalidtoken")
  check "Invalid token" "401" "$CODE"

  # ── [3] API ENDPOINTS ──
  printf "\n\033[1;33m[3/5] API ENDPOINTS\033[0m\n"
  ENDPOINTS=(
    "dashboard"
    "products"
    "products/categories"
    "sales?period=7d&limit=5"
    "analytics/finance?period=7d"
    "analytics/returns?period=30d"
    "analytics/geography"
    "analytics/unit-economics?period=30d"
    "analytics/brands?period=30d"
    "analytics/warehouses?period=30d"
    "analytics/trending?period=30d"
    "analytics/rnp?period=30d"
    "notifications"
    "sync/status"
    "sync/history"
  )
  for ep in "${ENDPOINTS[@]}"; do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/$ep" \
      -H "Authorization: Bearer $TOKEN")
    check "GET /api/v1/$ep" "200" "$CODE"
  done

  # ── [4] DATA VALIDATION ──
  printf "\n\033[1;33m[4/5] DATA VALIDATION\033[0m\n"
  python3 << PYEOF
import urllib.request, json, sys
token = "$TOKEN"
base = "$BASE_URL"
hdr = {"Authorization": f"Bearer {token}"}
ok = fail = 0

def get(path):
    req = urllib.request.Request(f"{base}/api/v1/{path}", headers=hdr)
    return json.loads(urllib.request.urlopen(req).read())

def test(name, cond):
    global ok, fail
    if cond:
        print(f"  \033[32mPASS\033[0m {name}"); ok += 1
    else:
        print(f"  \033[31mFAIL\033[0m {name}"); fail += 1

try:
    d = get("dashboard")
    test("Dashboard: has total_revenue", "total_revenue" in d)
    test("Dashboard: has total_orders", "total_orders" in d)

    d = get("analytics/finance?period=30d")
    test("Finance: has pnl", "pnl" in d)
    test("Finance: has margins", "margins" in d)

    d = get("analytics/returns?period=30d")
    test("Returns: has summary", "summary" in d)

    cats = get("products/categories")
    test("Categories: is array", isinstance(cats, list))
    test("Categories: count >= 1", len(cats) >= 1)

    h = get("../health")
    test("Health: postgres=true", h.get("postgres") == True)

except Exception as e:
    print(f"  \033[31mERROR\033[0m {e}"); fail += 1

with open("/tmp/sd_validation", "w") as f:
    f.write(f"{ok}:{fail}")
PYEOF
  V=$(cat /tmp/sd_validation 2>/dev/null || echo "0:0")
  V_OK=$(echo "$V" | cut -d: -f1)
  V_FAIL=$(echo "$V" | cut -d: -f2)
  ((PASS+=V_OK)); ((FAIL+=V_FAIL))
fi

# ── [5] FRONTEND PAGES ──
printf "\n\033[1;33m[5/5] FRONTEND PAGES\033[0m\n"
for pg in "/" "/login" "/products" "/sales" "/settings"; do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL$pg")
  check "GET $pg" "200" "$CODE"
done

# ── SUMMARY ──
TOTAL=$((PASS + FAIL))
printf "\n\033[1;33m══════════════════════════════════════\033[0m\n"
printf "  Total: %d | \033[32mPassed: %d\033[0m | \033[31mFailed: %d\033[0m\n" "$TOTAL" "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  printf "\n  \033[32m✅ ALL TESTS PASSED!\033[0m\n\n"; exit 0
else
  printf "\n  \033[31m❌ SOME TESTS FAILED\033[0m\n\n"; exit 1
fi
