#!/bin/bash

# Render Environment Expectations:
# - Linux OS with bash shell
# - curl available (standard)
# - Environment variables set in Render dashboard are available (e.g., $FIREBASE_API_KEY)
# - Internet access for downloading Flutter
# - Sufficient disk space for Flutter SDK (~0.5GB)
# - Build timeout: Default 15min, can be increased in Render settings
# - Static site publish directory: build/web

# Download Flutter 3.41.4, extract, set PATH, verify, and build with Firebase config
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.4-stable.tar.xz && \
tar xf flutter_linux_3.41.4-stable.tar.xz && \
export PATH="$PATH:$(pwd)/flutter/bin" && \
flutter --version && \
flutter build web --release --base-href / \
  --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY \
  --dart-define=FIREBASE_AUTH_DOMAIN=$FIREBASE_AUTH_DOMAIN \
  --dart-define=FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID \
  --dart-define=FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID \
  --dart-define=FIREBASE_APP_ID=$FIREBASE_APP_ID