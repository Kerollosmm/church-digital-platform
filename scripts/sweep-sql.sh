#!/usr/bin/env bash
# Full SQL suite sweep. Each file piped over stdin; run_all.sql skipped.
# Fails non-zero on TAP failures ('not ok' or '# Looks like you failed') or psql errors.
set -euo pipefail

cd "$(dirname "$0")/.."
OUTDIR="${TMPDIR:-/tmp}/sweep-out"
mkdir -p "$OUTDIR"
rm -f "$OUTDIR"/*.log

pass=0
fail=0
faillist=""

for f in supabase/tests/*.sql; do
  b="$(basename "$f")"
  case "$b" in run_all.sql) continue ;; esac
  printf '%-45s : ' "$b"
  if docker exec -i supabase_db_church psql -U postgres -d postgres \
       -v ON_ERROR_STOP=1 --no-psqlrc < "$f" > "$OUTDIR/$b.log" 2>&1; then
    if grep -qiE '^not ok|# Looks like you failed' "$OUTDIR/$b.log"; then
      echo -e "\033[31mFAIL(TAP assertion)\033[0m"
      fail=$((fail+1)); faillist="$faillist $b"
    else
      echo -e "\033[32mPASS\033[0m"
      pass=$((pass+1))
    fi
  else
    echo -e "\033[31mFAIL(Postgres error)\033[0m"
    fail=$((fail+1)); faillist="$faillist $b"
  fi
done

echo "=========================================="
echo "TOTAL SUITES: $((pass+fail)) | PASS=$pass | FAIL=$fail"
echo "=========================================="

if [ "$fail" -gt 0 ]; then
  echo -e "\033[31mFAILING SUITES:$faillist\033[0m"
  exit 1
else
  echo -e "\033[32mAll $pass SQL suites passed!\033[0m"
  exit 0
fi
