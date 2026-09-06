#!/usr/bin/env bash
set -euo pipefail

# Ensure paths loaded
export PATH="$HOME/flutter/bin:$HOME/.deno/bin:$PATH"

echo "==> [Jules Test] Running mobile checks..."
(cd apps/mobile && flutter test)

echo "==> [Jules Test] Running admin checks..."
(cd apps/admin && flutter test)

echo "==> [Jules Test] Running Deno Edge function tests..."
deno test --allow-env --allow-net supabase/functions/

echo "==> [Jules Test] All test suites PASSED!"
