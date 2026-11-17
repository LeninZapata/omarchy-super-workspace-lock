#!/usr/bin/env bash
# Corre todas las pruebas: sintaxis QML (qmlformat), lógica (node) y python.
# Sale con error si alguna falla. Correrlo ANTES de `omarchy restart shell`: un QML
# con la sintaxis rota tumba el servicio entero (y con él el bloqueo).
set -e
cd "$(dirname "$0")"
QMLFORMAT=/usr/lib/qt6/bin/qmlformat
if [ -x "$QMLFORMAT" ]; then
  for q in ../*.qml; do "$QMLFORMAT" "$q" >/dev/null || { echo "sintaxis QML rota: $q"; exit 1; }; done
  echo "qml ok"
fi
for t in test-*.mjs; do node "$t"; done
for t in test_*.py; do python3 -I "$t"; done
