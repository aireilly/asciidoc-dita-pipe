#!/usr/bin/env bash
set -euo pipefail

# entrypoint.sh — Container entrypoint for single-file AsciiDoc-to-DITA pipeline
#
# Usage:
#   docker run -v /path/to/src:/input -v /path/to/output:/output asciidoc-dita-pipe input.adoc
#
# The input file is expected at /input/<filename>.adoc
# If the file is an assembly with include:: directives, mount the full source tree at /input.
# Output lands in /output/dita/ and /output/html/.

INPUT_DIR="/input"
OUTPUT_DIR="/output"
WORK="/work"
BUILD="${WORK}/build"
PIPE="/pipeline"

usage() {
    echo "Usage: docker run -v /path/to/src:/input -v /path/to/out:/output asciidoc-dita-pipe <file.adoc>"
    echo ""
    echo "  Mount your AsciiDoc source directory at /input."
    echo "  The specified .adoc file is processed through the DITA pipeline."
    echo "  Content type is detected from :_mod-docs-content-type: attribute or filename prefix."
    echo ""
    echo "  Assembly files are processed directly (include:: targets must be resolvable from /input)."
    echo "  Module files (concept/procedure/reference) are wrapped in a minimal document structure."
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

INPUT_FILE="$1"

# Resolve the input file
if [ -f "${INPUT_DIR}/${INPUT_FILE}" ]; then
    INPUT_PATH="${INPUT_DIR}/${INPUT_FILE}"
elif [ -f "${INPUT_FILE}" ]; then
    INPUT_PATH="${INPUT_FILE}"
else
    echo "ERROR: File not found: ${INPUT_FILE}"
    echo "       Looked in ${INPUT_DIR}/${INPUT_FILE} and ${INPUT_FILE}"
    exit 1
fi

BASENAME=$(basename "${INPUT_PATH}" .adoc)
INPUT_PARENT=$(dirname "${INPUT_PATH}")

echo "== Processing: ${INPUT_FILE}"

# --- Detect content type ---
CONTENT_TYPE=""
MOD_TYPE=$(grep -m1 '^:_mod-docs-content-type:' "${INPUT_PATH}" | sed 's/^:_mod-docs-content-type:\s*//' | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]') || true

if [ -n "${MOD_TYPE}" ]; then
    CONTENT_TYPE="${MOD_TYPE}"
    echo "== Content type (attribute): ${CONTENT_TYPE}"
else
    # Filename prefix fallback
    case "${BASENAME}" in
        assembly_*) CONTENT_TYPE="ASSEMBLY" ;;
        proc_*)     CONTENT_TYPE="PROCEDURE" ;;
        con_*)      CONTENT_TYPE="CONCEPT" ;;
        ref_*)      CONTENT_TYPE="REFERENCE" ;;
        *)          CONTENT_TYPE="CONCEPT"
                    echo "== WARNING: No content type detected, defaulting to CONCEPT" ;;
    esac
    echo "== Content type (filename prefix): ${CONTENT_TYPE}"
fi

# --- Prepare working directory ---
mkdir -p "${BUILD}/docbook" "${BUILD}/dita-raw" "${BUILD}/dita-specialized"
mkdir -p "${OUTPUT_DIR}/dita/topics" "${OUTPUT_DIR}/dita/maps" "${OUTPUT_DIR}/html"

# --- Build source tree for asciidoctor ---
# Copy input tree so includes resolve correctly
SRC_WORK="${WORK}/src"
mkdir -p "${SRC_WORK}"
cp -a "${INPUT_DIR}/." "${SRC_WORK}/"

# Determine relative path of input file within /input
REL_PATH=$(realpath --relative-to="${INPUT_DIR}" "${INPUT_PATH}" 2>/dev/null || echo "${INPUT_FILE}")

# For modules, create a wrapper master.adoc so the pipeline has a top-level document
if [ "${CONTENT_TYPE}" != "ASSEMBLY" ]; then
    echo "== Module detected — generating wrapper document"
    WRAPPER="${SRC_WORK}/_wrapper_master.adoc"
    cat > "${WRAPPER}" <<ADOC
// Auto-generated wrapper for single-module pipeline
:_mod-docs-content-type: ASSEMBLY

[id="${BASENAME}"]
= ${BASENAME}

include::${REL_PATH}[leveloffset=+1]
ADOC
    MASTER_FILE="_wrapper_master.adoc"
else
    MASTER_FILE="${REL_PATH}"
fi

echo "== Master file: ${MASTER_FILE}"

# --- Stage 0: Build manifest ---
echo "== Stage 0: Building content-type manifest"
python3 "${PIPE}/scripts/build-manifest.py" "${SRC_WORK}" > "${BUILD}/content-type-manifest.xml"
ENTRY_COUNT=$(grep -c '<entry' "${BUILD}/content-type-manifest.xml" || echo 0)
echo "   Manifest: ${ENTRY_COUNT} entries"

# --- Stage 1: AsciiDoc to DocBook ---
echo "== Stage 1: AsciiDoc → DocBook"
cd "${SRC_WORK}" && asciidoctor -b docbook5 \
    -a imagesdir=images \
    "${MASTER_FILE}" \
    -o "${BUILD}/docbook/master.xml"
cd "${WORK}"
echo "   DocBook: $(wc -c < "${BUILD}/docbook/master.xml") bytes"

# --- Stage 2: Enrich DocBook with content types ---
echo "== Stage 2: Enriching DocBook"
java -jar "${PIPE}/SaxonHE12-4J/saxon-he-12.4.jar" -dtd:off \
    -xsl:"${PIPE}/xsl/enrich-docbook.xsl" \
    -s:"${BUILD}/docbook/master.xml" \
    -o:"${BUILD}/docbook/master-enriched.xml" \
    "manifest-uri=file://${BUILD}/content-type-manifest.xml"
echo "   Enriched: $(wc -c < "${BUILD}/docbook/master-enriched.xml") bytes"

# --- Stage 3: DocBook to DITA (dbdita) ---
echo "== Stage 3: DocBook → DITA (dbdita)"
mkdir -p "${BUILD}/dita-raw"
java -jar "${PIPE}/SaxonHE12-4J/saxon-he-12.4.jar" -dtd:off \
    -xsl:"${PIPE}/dbdita/db2dita/docbook2dita.xsl" \
    -s:"${BUILD}/docbook/master-enriched.xml" \
    -o:"${BUILD}/dita-raw/master-composite.dita"
echo "   Raw DITA: $(wc -c < "${BUILD}/dita-raw/master-composite.dita") bytes"

# --- Stage 4: Specialize topics ---
echo "== Stage 4: Specializing topics"
mkdir -p "${BUILD}/dita-specialized"
sed '/DOCTYPE/,/>/d' "${BUILD}/dita-raw/master-composite.dita" > "${BUILD}/dita-raw/master-composite-nodtd.dita"
java -jar "${PIPE}/SaxonHE12-4J/saxon-he-12.4.jar" -dtd:off \
    -xsl:"${PIPE}/xsl/specialize-topics.xsl" \
    -s:"${BUILD}/dita-raw/master-composite-nodtd.dita" \
    -o:"${BUILD}/dita-specialized/master-composite.dita"
echo "   Specialized: $(wc -c < "${BUILD}/dita-specialized/master-composite.dita") bytes"

# --- Stage 5: Split into individual files + ditamap ---
echo "== Stage 5: Splitting into individual files"
java -jar "${PIPE}/SaxonHE12-4J/saxon-he-12.4.jar" -dtd:off \
    -xsl:"${PIPE}/xsl/split-and-map.xsl" \
    -s:"${BUILD}/dita-specialized/master-composite.dita" \
    -o:"${BUILD}/split-result.xml" \
    "outdir=file://${OUTPUT_DIR}/dita"
TOPIC_COUNT=$(find "${OUTPUT_DIR}/dita/topics" -name '*.dita' 2>/dev/null | wc -l)
MAP_COUNT=$(find "${OUTPUT_DIR}/dita/maps" -name '*.ditamap' 2>/dev/null | wc -l)
echo "   Split: ${TOPIC_COUNT} topics, ${MAP_COUNT} maps"

# --- Copy images ---
echo "== Copying images"
if find "${SRC_WORK}" -name '*.png' -o -name '*.jpg' -o -name '*.gif' -o -name '*.svg' 2>/dev/null | head -1 | grep -q .; then
    mkdir -p "${OUTPUT_DIR}/dita/images"
    find "${SRC_WORK}" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.gif' -o -name '*.svg' \) -exec cp {} "${OUTPUT_DIR}/dita/images/" \;
    IMAGE_COUNT=$(ls "${OUTPUT_DIR}/dita/images/" 2>/dev/null | wc -l)
    echo "   Images: ${IMAGE_COUNT} files"
else
    echo "   No images found"
fi

# --- Find the ditamap ---
DITAMAP=$(find "${OUTPUT_DIR}/dita" -maxdepth 1 -name '*.ditamap' | head -1)
if [ -z "${DITAMAP}" ]; then
    echo "WARNING: No ditamap found in output — skipping HTML generation"
    echo "== Done. DITA output is in ${OUTPUT_DIR}/dita/"
    exit 0
fi

# --- Validate / generate HTML5 ---
echo "== Generating HTML5 output"
if command -v dita >/dev/null 2>&1; then
    dita -i "${DITAMAP}" -f html5 -o "${OUTPUT_DIR}/html" \
        --args.cssroot="${PIPE}/css" --args.css=custom.css --args.copycss=yes 2>&1 || {
        echo "WARNING: HTML5 generation completed with errors (see above)"
    }
    HTML_COUNT=$(find "${OUTPUT_DIR}/html" -name '*.html' 2>/dev/null | wc -l)
    echo "   HTML: ${HTML_COUNT} pages"
else
    echo "WARNING: dita command not found — skipping HTML generation"
fi

echo ""
echo "== Done."
echo "   DITA output: ${OUTPUT_DIR}/dita/"
echo "   HTML output: ${OUTPUT_DIR}/html/"
