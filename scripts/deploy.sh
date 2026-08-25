#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[UrbanEye] Deploy da infraestrutura..."
# Exemplo de passos futuros:
# 1. flutter pub get
# 2. firebase deploy --only firestore,functions,storage
# 3. flutter build apk --release

printf "\n[UrbanEye] Pipeline de deploy planejada. Ajustar conforme ambiente real.\n"
