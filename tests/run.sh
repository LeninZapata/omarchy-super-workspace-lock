#!/usr/bin/env bash
# Corre todas las pruebas de lógica (node). Sale con error si alguna falla.
set -e
cd "$(dirname "$0")"
for t in test-*.mjs; do node "$t"; done
