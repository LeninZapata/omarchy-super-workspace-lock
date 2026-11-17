#!/usr/bin/env bash
# Corre todas las pruebas de lógica (node y python). Sale con error si alguna falla.
set -e
cd "$(dirname "$0")"
for t in test-*.mjs; do node "$t"; done
for t in test_*.py; do python3 -I "$t"; done
