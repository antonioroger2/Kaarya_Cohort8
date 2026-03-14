#!/bin/bash

# Render Environment Expectations:
# - Linux OS with bash shell
# - curl, grep, sed available (standard)
# - jq not guaranteed (avoid if possible)
# - Environment variables set in Render dashboard (e.g., FIREBASE_API_KEY) are available as $FIREBASE_API_KEY
# - Internet access for downloading Flutter and GitHub API
# - Sufficient disk space for Flutter SDK (~1GB)
# - Build timeout: Default 15min, can be increased in Render settings
# - Static site publish directory: build/web

# Fetch latest stable Flutter version from GitHub API (avoids jq dependency)
LATEST_FLUTTER=$(curl -s https://api.github.com/repos/flutter/flutter/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')

# Download and extract Flutter
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${LATEST_FLUTTER}-stable.tar.xz
tar xf flutter_linux_${LATEST_FLUTTER}-stable.tar.xz

# Set PATH and verify
export PATH="$PATH:$(pwd)/flutter/bin"
flutter --version

# Build with web-specific options and Firebase config from env vars
flutter build web --release --base-href / \
  --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY \
  --dart-define=FIREBASE_AUTH_DOMAIN=$FIREBASE_AUTH_DOMAIN \
  --dart-define=FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID \
  --dart-define=FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID \
  --dart-define=FIREBASE_APP_ID=$FIREBASE_APP_ID