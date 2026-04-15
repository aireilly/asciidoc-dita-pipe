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

# --- Colour helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()  { echo -e "${BLUE}${BOLD}▶${RESET} $*"; }
stage() { echo -e "${CYAN}${BOLD}[$1]${RESET} $2"; }
detail(){ echo -e "  ${DIM}$*${RESET}"; }
ok()    { echo -e "  ${GREEN}✔${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET} $*"; }
err()   { echo -e "${RED}${BOLD}✖${RESET} $*"; }

usage() {
    echo -e "${BOLD}Usage:${RESET} docker run -v /path/to/src:/input -v /path/to/out:/output asciidoc-dita-pipe [OPTIONS] <file.adoc>"
    echo ""
    echo "  Mount your AsciiDoc source directory at /input."
    echo "  The specified .adoc file is processed through the DITA pipeline."
    echo "  Content type is detected from :_mod-docs-content-type: attribute or filename prefix."
    echo ""
    echo "  Assembly files are processed directly (include:: targets must be resolvable from /input)."
    echo "  Module files (concept/procedure/reference) are wrapped in a minimal document structure."
    echo ""
    echo -e "  ${BOLD}Options:${RESET}"
    echo "    --dita-version 1.3|2.0   DITA output version (default: 1.3)"
    exit 1
}

# --- Parse options ---
DITA_VERSION="1.3"
while [ $# -gt 0 ]; do
    case "$1" in
        --dita-version)
            DITA_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -lt 1 ]; then
    usage
fi

if [ "${DITA_VERSION}" != "1.3" ] && [ "${DITA_VERSION}" != "2.0" ]; then
    err "Invalid DITA version: ${DITA_VERSION} (must be 1.3 or 2.0)"
    exit 1
fi

INPUT_FILE="$1"

# Resolve the input file
if [ -f "${INPUT_DIR}/${INPUT_FILE}" ]; then
    INPUT_PATH="${INPUT_DIR}/${INPUT_FILE}"
elif [ -f "${INPUT_FILE}" ]; then
    INPUT_PATH="${INPUT_FILE}"
else
    err "File not found: ${INPUT_FILE}"
    detail "Looked in ${INPUT_DIR}/${INPUT_FILE} and ${INPUT_FILE}"
    exit 1
fi

BASENAME=$(basename "${INPUT_PATH}" .adoc)
INPUT_PARENT=$(dirname "${INPUT_PATH}")

info "Processing: ${BOLD}${INPUT_FILE}${RESET} (DITA ${DITA_VERSION})"

# --- Detect content type ---
CONTENT_TYPE=""
MOD_TYPE=$(grep -m1 '^:_mod-docs-content-type:' "${INPUT_PATH}" | sed 's/^:_mod-docs-content-type:\s*//' | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]') || true

if [ -n "${MOD_TYPE}" ]; then
    CONTENT_TYPE="${MOD_TYPE}"
    ok "Content type (attribute): ${BOLD}${CONTENT_TYPE}${RESET}"
else
    # Filename prefix fallback
    case "${BASENAME}" in
        assembly_*) CONTENT_TYPE="ASSEMBLY" ;;
        proc_*)     CONTENT_TYPE="PROCEDURE" ;;
        con_*)      CONTENT_TYPE="CONCEPT" ;;
        ref_*)      CONTENT_TYPE="REFERENCE" ;;
        *)          CONTENT_TYPE="CONCEPT"
                    warn "No content type detected, defaulting to CONCEPT" ;;
    esac
    ok "Content type (filename prefix): ${BOLD}${CONTENT_TYPE}${RESET}"
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
    detail "Module detected — generating wrapper document"
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

detail "Master file: ${MASTER_FILE}"

# --- Stage 0: Build manifest ---
stage "0" "Building content-type manifest"
python3 "${PIPE}/scripts/build-manifest.py" "${SRC_WORK}" > "${BUILD}/content-type-manifest.xml"
ENTRY_COUNT=$(grep -c '<entry' "${BUILD}/content-type-manifest.xml" || echo 0)
ok "Manifest: ${ENTRY_COUNT} entries"

# --- Stage 1: AsciiDoc to DocBook ---
stage "1" "AsciiDoc → DocBook"
cd "${SRC_WORK}" && asciidoctor -b docbook5 \
    -a imagesdir=images \
    "${MASTER_FILE}" \
    -o "${BUILD}/docbook/master.xml"
cd "${WORK}"
ok "DocBook: $(wc -c < "${BUILD}/docbook/master.xml") bytes"

# --- Stage 2: Enrich DocBook with content types ---
stage "2" "Enriching DocBook"
java -jar "${PIPE}/SaxonHE12-4J/saxon-he-12.4.jar" -dtd:off \
    -xsl:"${PIPE}/xsl/enrich-docbook.xsl" \
    -s:"${BUILD}/docbook/master.xml" \
    -o:"${BUILD}/docbook/master-enriched.xml" \
    "manifest-uri=file://${BUILD}/content-type-manifest.xml"
ok "Enriched: $(wc -c < "${BUILD}/docbook/master-enriched.xml") bytes"

# --- Stage 3: DocBook to DITA (dbdita) ---
stage "3" "DocBook → DITA (dbdita)"
mkdir -p "${BUILD}/dita-raw"
java -jar "${PIPE}/SaxonHE12-4J/saxon-he-12.4.jar" -dtd:off \
    -xsl:"${PIPE}/dbdita/db2dita/docbook2dita.xsl" \
    -s:"${BUILD}/docbook/master-enriched.xml" \
    -o:"${BUILD}/dita-raw/master-composite.dita" \
    "dita-version=${DITA_VERSION}"
ok "Raw DITA: $(wc -c < "${BUILD}/dita-raw/master-composite.dita") bytes"

# --- Stage 4: Specialize topics ---
stage "4" "Specializing topics"
mkdir -p "${BUILD}/dita-specialized"
sed '/DOCTYPE/,/>/d' "${BUILD}/dita-raw/master-composite.dita" > "${BUILD}/dita-raw/master-composite-nodtd.dita"
java -jar "${PIPE}/SaxonHE12-4J/saxon-he-12.4.jar" -dtd:off \
    -xsl:"${PIPE}/xsl/specialize-topics.xsl" \
    -s:"${BUILD}/dita-raw/master-composite-nodtd.dita" \
    -o:"${BUILD}/dita-specialized/master-composite.dita"
ok "Specialized: $(wc -c < "${BUILD}/dita-specialized/master-composite.dita") bytes"

# --- Stage 5: Split into individual files + ditamap ---
stage "5" "Splitting into individual files"
java -jar "${PIPE}/SaxonHE12-4J/saxon-he-12.4.jar" -dtd:off \
    -xsl:"${PIPE}/xsl/split-and-map.xsl" \
    -s:"${BUILD}/dita-specialized/master-composite.dita" \
    -o:"${BUILD}/split-result.xml" \
    "outdir=file://${OUTPUT_DIR}/dita" \
    "dita-version=${DITA_VERSION}"
TOPIC_COUNT=$(find "${OUTPUT_DIR}/dita/topics" -name '*.dita' 2>/dev/null | wc -l)
MAP_COUNT=$(find "${OUTPUT_DIR}/dita/maps" -name '*.ditamap' 2>/dev/null | wc -l)
ok "Split: ${TOPIC_COUNT} topics, ${MAP_COUNT} maps"

# --- Copy images ---
stage "+" "Copying images"
if find "${SRC_WORK}" -name '*.png' -o -name '*.jpg' -o -name '*.gif' -o -name '*.svg' 2>/dev/null | head -1 | grep -q .; then
    mkdir -p "${OUTPUT_DIR}/dita/images"
    find "${SRC_WORK}" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.gif' -o -name '*.svg' \) -exec cp {} "${OUTPUT_DIR}/dita/images/" \;
    IMAGE_COUNT=$(ls "${OUTPUT_DIR}/dita/images/" 2>/dev/null | wc -l)
    ok "Images: ${IMAGE_COUNT} files"
else
    detail "No images found"
fi

# --- Find the ditamap ---
DITAMAP=$(find "${OUTPUT_DIR}/dita" -maxdepth 1 -name '*.ditamap' | head -1)
if [ -z "${DITAMAP}" ]; then
    warn "No ditamap found in output — skipping HTML generation"
    info "Done. DITA output is in ${OUTPUT_DIR}/dita/"
    exit 0
fi

# --- Generate HTML5 ---
# DITA-OT with generate.copy.outer=3 mirrors the input directory name in
# the output tree.  Symlink the DITA output into a directory named "html"
# so the mirrored prefix becomes the output folder itself:
#   {output-dir}/html/index.html + {output-dir}/html/topics/*.html
stage "html" "Generating HTML5 output"
if command -v dita >/dev/null 2>&1; then
    DITA_LINK="${BUILD}/html"
    ln -sfn "${OUTPUT_DIR}/dita" "${DITA_LINK}"
    dita -i "${DITA_LINK}/$(basename "${DITAMAP}")" -f html5 \
        -o "${OUTPUT_DIR}" \
        --generate.copy.outer=3 \
        --outer.control=warn \
        --args.cssroot="${PIPE}/css" --args.css=custom.css --args.copycss=yes 2>&1 || {
        warn "HTML5 generation completed with errors (see above)"
    }
    rm -f "${DITA_LINK}"

    HTML_COUNT=$(find "${OUTPUT_DIR}/html" -name '*.html' | wc -l)
    ok "HTML: ${HTML_COUNT} pages"
else
    warn "dita command not found — skipping HTML generation"
fi

echo ""
echo -e "${GREEN}${BOLD}Done.${RESET} Check the output folder"
echo -e "  ${DIM}DITA → ${OUTPUT_DIR}/dita/${RESET}"
echo -e "  ${DIM}HTML → ${OUTPUT_DIR}/html/${RESET}"
