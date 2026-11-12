#!/bin/zsh
# Renders the widget without placing it on the desktop: compiles the widget views
# with a main.swift that uses ImageRenderer. Usage: tools/widget-snapshots.sh [folder]
set -e
cd "$(dirname "$0")/.."
OUT="${1:-snapshots}"
mkdir -p "$OUT" build.noindex/widget-snapshot
swiftc -parse-as-library -D SNAPSHOT_HARNESS -O -module-name LegroomWidgetSnapshot \
  -o build.noindex/widget-snapshot/render \
  LegroomWidget/*.swift Lupa/Models/WidgetSnapshot.swift Lupa/Models/Volume.swift \
  Lupa/Models/Memory.swift Lupa/Models/Formatting.swift Lupa/Views/DiskHealth.swift \
  tools/widget-snapshot/main.swift 2>&1 | grep -v "^$" || true
build.noindex/widget-snapshot/render "$OUT"
