#!/usr/bin/env bash
set -euo pipefail

echo "==> [Jules Setup] Starting environment configuration..."

# 1. System packages
if command -v apt-get >/dev/null 2>&1; then
  echo "==> [1/5] Installing OS dependencies..."
  SUDO=""
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
  $SUDO apt-get update -y -qq
  $SUDO apt-get install -y -qq --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    build-essential \
    postgresql-client
fi

# 2. Node & npm dependencies
echo "==> [2/5] Installing root npm dependencies..."
if [ -f "package.json" ]; then
  npm ci || npm install
fi

# 3. Supabase CLI
if ! command -v supabase >/dev/null 2>&1; then
  echo "==> [3/5] Installing Supabase CLI..."
  npm install -g supabase --silent || true
fi

# 4. Deno SDK
if ! command -v deno >/dev/null 2>&1; then
  echo "==> [4/5] Installing Deno..."
  curl -fsSL https://deno.land/install.sh | sh -s -- -y
  export DENO_INSTALL="$HOME/.deno"
  export PATH="$DENO_INSTALL/bin:$PATH"
fi

# 5. Flutter SDK
if ! command -v flutter >/dev/null 2>&1; then
  echo "==> [5/5] Installing Flutter SDK (stable)..."
  FLUTTER_DIR="$HOME/flutter"
  if [ ! -d "$FLUTTER_DIR" ]; then
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
fi

# Persist environment variables for subshells
mkdir -p "$HOME"
for RC in "$HOME/.bashrc" "$HOME/.profile"; do
  touch "$RC"
  if ! grep -q 'flutter/bin' "$RC"; then
    echo 'export PATH="$HOME/flutter/bin:$HOME/.deno/bin:$PATH"' >> "$RC"
  fi
done

# Disable analytics and precache
flutter config --no-analytics >/dev/null 2>&1 || true
flutter precache

# 6. Fetch Flutter packages
echo "==> Fetching Flutter dependencies for apps/mobile..."
(cd apps/mobile && flutter pub get)

echo "==> Fetching Flutter dependencies for apps/admin..."
(cd apps/admin && flutter pub get)

echo "==> [Jules Setup] Environment ready!"
flutter --version
deno --version
supabase --version
