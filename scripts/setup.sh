#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[UrbanEye] Configurando estrutura do projeto..."
mkdir -p "$ROOT_DIR/apps/mobile/lib" \
         "$ROOT_DIR/apps/mobile/test" \
         "$ROOT_DIR/apps/mobile/assets" \
         "$ROOT_DIR/backend/functions/src" \
         "$ROOT_DIR/backend/firebase/firestore/schema" \
         "$ROOT_DIR/backend/firebase/firestore/indexes" \
         "$ROOT_DIR/backend/firebase/storage" \
         "$ROOT_DIR/backend/firebase/auth" \
         "$ROOT_DIR/backend/firebase/rules" \
         "$ROOT_DIR/docs/architecture" \
         "$ROOT_DIR/docs/roadmap" \
         "$ROOT_DIR/scripts"

echo "[UrbanEye] Estrutura pronta."
