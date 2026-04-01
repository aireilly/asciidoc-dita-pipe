#!/usr/bin/env bash
# Compare content coverage between AsciiDoc HTML and DITA HTML output.
# Usage: ./scripts/compare-content.sh
#
# Extracts sentences from both outputs and reports coverage percentage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD="$PROJECT_DIR/build"
OUT="$PROJECT_DIR/out"

ADOC_HTML="$BUILD/asciidoc-html/master.html"
DITA_HTML_DIR="$OUT/html5/topics"

if [ ! -f "$ADOC_HTML" ]; then
  echo "ERROR: AsciiDoc HTML not found at $ADOC_HTML"
  echo "Run: cd src/configuring-and-managing-networking && asciidoctor master.adoc -o ../../build/asciidoc-html/master.html"
  exit 1
fi

if [ ! -d "$DITA_HTML_DIR" ]; then
  echo "ERROR: DITA HTML not found at $DITA_HTML_DIR"
  echo "Run: make validate"
  exit 1
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Extracting text from AsciiDoc HTML..."
html2text "$ADOC_HTML" 2>/dev/null | \
  sed 's/[[:space:]]\+/ /g' | \
  tr '.' '\n' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
  grep -E '.{20,}' | \
  sort -u > "$TMPDIR/adoc-sentences.txt"

echo "Extracting text from DITA HTML..."
cat "$DITA_HTML_DIR"/*.html 2>/dev/null | \
  html2text 2>/dev/null | \
  sed 's/[[:space:]]\+/ /g' | \
  tr '.' '\n' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
  grep -E '.{20,}' | \
  sort -u > "$TMPDIR/dita-sentences.txt"

ADOC_COUNT=$(wc -l < "$TMPDIR/adoc-sentences.txt")
DITA_COUNT=$(wc -l < "$TMPDIR/dita-sentences.txt")

echo ""
echo "AsciiDoc sentences (20+ chars): $ADOC_COUNT"
echo "DITA sentences (20+ chars):     $DITA_COUNT"

# Find sentences in AsciiDoc but not in DITA
comm -23 "$TMPDIR/adoc-sentences.txt" "$TMPDIR/dita-sentences.txt" > "$TMPDIR/missing.txt"
MISSING=$(wc -l < "$TMPDIR/missing.txt")

COVERED=$((ADOC_COUNT - MISSING))
if [ "$ADOC_COUNT" -gt 0 ]; then
  PCT=$(echo "scale=1; $COVERED * 100 / $ADOC_COUNT" | bc)
else
  PCT="0"
fi

echo ""
echo "Missing from DITA:              $MISSING"
echo "Coverage:                       $COVERED / $ADOC_COUNT ($PCT%)"
echo ""

if [ "$MISSING" -gt 0 ]; then
  echo "=== Missing sentences (first 30) ==="
  head -30 "$TMPDIR/missing.txt"

  # Save full missing list
  cp "$TMPDIR/missing.txt" "$BUILD/missing-sentences.txt"
  echo ""
  echo "Full list saved to: $BUILD/missing-sentences.txt"
fi
