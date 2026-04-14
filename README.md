# AsciiDoc to DITA Pipeline

Multi-stage pipeline that transforms modular AsciiDoc documentation (Red Hat-style assemblies, concepts, procedures, references) into DITA topics with proper specialization, individual topic files, sub-assembly maps, and a master ditamap.

> [!NOTE]
> A container build is available at [quay.io/repository/rhn_support_aireilly/asciidoc-dita-pipe](https://quay.io/repository/rhn_support_aireilly/asciidoc-dita-pipe).

## Quick start

The pipeline is available as a container image. No local dependencies required beyond `podman` or `docker`.

```bash
cd your-docs-repo
mkdir -p out

podman run --rm \
  -v "$PWD":/input:ro,z \
  -v "$PWD"/out:/output:z \
  quay.io/rhn_support_aireilly/asciidoc-dita-pipe \
  path/to/your-assembly.adoc
```

The input file's content type is detected automatically from the `:_mod-docs-content-type:` attribute or filename prefix (`assembly_`, `proc_`, `con_`, `ref_`). Assemblies are processed directly; standalone modules are wrapped in a minimal document structure.

Mount the root of your docs repo at `/input` so that `include::` directives resolve correctly.

## Output structure

```
out/
  dita/
    master.ditamap              # Top-level map
    maps/
      *.ditamap                 # Sub-assembly maps
    topics/
      *.dita                    # Specialized topics (concept, task, reference)
    images/
      *.png                     # Copied images
  html/
    index.html                  # HTML5 table of contents
    topics/
      *.html                    # Rendered topic pages
    custom.css
```

All `index.html` links resolve to `topics/*.html`. Cross-references to other assemblies outside the build scope are expected to be unresolved.

## Pipeline stages

The pipeline transforms content through 6 stages:

```
input.adoc
    |
    v  [Stage 0] scripts/build-manifest.py
build/content-type-manifest.xml
    |
    v  [Stage 1] asciidoctor -b docbook5
build/docbook/master.xml
    |
    v  [Stage 2] xsl/enrich-docbook.xsl
build/docbook/master-enriched.xml
    |
    v  [Stage 3] dbdita/db2dita/docbook2dita.xsl
build/dita-raw/master-composite.dita
    |
    v  [Stage 4] xsl/specialize-topics.xsl
build/dita-specialized/master-composite.dita
    |
    v  [Stage 5] xsl/split-and-map.xsl
out/dita/{master.ditamap, topics/*.dita, maps/*.ditamap}
    |
    v  [HTML] dita -f html5
out/html/{index.html, topics/*.html}
```

### Stage 0: Content-type manifest

`scripts/build-manifest.py` scans all `.adoc` files and builds an XML manifest mapping section IDs to DITA topic types:

1. Checks for `:_mod-docs-content-type:` attribute (primary)
2. Falls back to filename prefix: `con_` -> concept, `proc_` -> task, `ref_` -> reference

### Stage 1: AsciiDoc to DocBook5

Converts the AsciiDoc source to DocBook5 XML using asciidoctor.

### Stage 2: Enrich DocBook

`xsl/enrich-docbook.xsl` reads the manifest and injects `role="concept|task|reference|assembly"` attributes onto DocBook `<section>` elements. This metadata survives the dbdita transform and drives topic specialization.

### Stage 3: dbdita transform

Runs the IBM dbdita DocBook-to-DITA transform via Saxon. Produces a single composite DITA file with all topics nested under a `<dita>` root. All topics are generic `<topic>` at this stage.

### Stage 4: Specialize and clean

`xsl/specialize-topics.xsl` transforms generic `<topic>` elements into proper DITA specialized types:

- `<topic>` with concept role/prefix -> `<concept>` with `<conbody>`
- `<topic>` with task role/prefix -> `<task>` with `<taskbody>` containing `<prereq>`, `<context>`, `<steps>/<step>/<cmd>`, `<result>`
- `<topic>` with reference role/prefix -> `<reference>` with `<refbody>` containing `<section>` wrappers

Also cleans up:
- Removes `outputclass="db.*"` artifacts from dbdita
- Removes empty prolog/metadata placeholders
- Fixes image paths for correct relative resolution
- Removes invalid `frame` attribute values
- Strips `xml:lang` from nested topics

### Stage 5: Split and generate maps

`xsl/split-and-map.xsl` splits the composite into individual files:

- Each topic -> `topics/{id}.dita` with proper DOCTYPE declaration
- Assembly topics with children -> `maps/{id}.ditamap` (sub-maps)
- Top-level -> `master.ditamap` with `<mapref>` to sub-maps and `<topicref>` to standalone topics

## Content-type detection

Topic specialization uses a two-tier detection strategy:

1. **Primary: `:_mod-docs-content-type:` attribute** in the source `.adoc` file
   - `CONCEPT` -> `<concept>`
   - `PROCEDURE` -> `<task>`
   - `REFERENCE` -> `<reference>`
   - `ASSEMBLY` -> `<topic>` (structural container)

2. **Fallback: filename prefix**
   - `con_*.adoc` -> `<concept>`
   - `proc_*.adoc` -> `<task>`
   - `ref_*.adoc` -> `<reference>`
   - `assembly_*.adoc` -> `<topic>`

## Task body restructuring

The pipeline detects AsciiDoc procedural sections and maps them to DITA task structure:

| AsciiDoc section | DITA element |
|-----------------|--------------|
| Abstract/intro paragraphs | `<context>` |
| Prerequisites + list | `<prereq>` |
| Procedure + ordered list | `<steps>/<step>/<cmd>` |
| Procedure + unordered list | `<steps-unordered>/<step>/<cmd>` |
| Verification section | `<result>` |
| Troubleshooting section | `<tasktroubleshooting>` |
| Additional resources / Next steps | `<postreq>` |

### Section title detection

Section titles (Prerequisites, Procedure, Verification, etc.) are detected using a two-tier strategy:

1. **Primary: `outputclass="db.title"`** — The dbdita transform preserves DocBook `<title>` elements as `<p outputclass="db.title">`. This attribute is the most reliable indicator.
2. **Fallback: exact text match** — For elements without the `db.title` attribute, the pipeline matches the exact normalized text (e.g., `normalize-space(.) = 'Procedure'`).

> [!WARNING]
> The pipeline avoids `contains()` matching (e.g., matching "procedure" inside "The procedure below...") to prevent false positives that would misclassify content paragraphs as section boundaries.

### Step extraction

Each `<step>` contains:
- `<cmd>` — the first `<p>` child's inline content (text, `<codeph>`, `<xref>`, etc.)
- `<info>` — any remaining content: additional `<p>` elements, `<pre>` code blocks, `<note>` elements, nested lists

## Reference body restructuring

> [!IMPORTANT]
> Reference topics (`<reference>`) use `<refbody>` which has a strict content model — it only allows `<section>`, `<table>`, `<simpletable>`, `<properties>`, and `<example>` as direct children. Bare `<p>`, `<ul>`, `<ol>`, `<pre>`, and `<note>` elements are invalid.

The pipeline uses `for-each-group` with `group-adjacent` to:
- Pass `<table>` and `<example>` elements through directly (valid refbody children)
- Wrap all other block content in `<section>` elements

## Content coverage

The pipeline achieves **97% word coverage** compared to direct `asciidoctor` HTML output, validated by extracting text via `html2text` from both outputs.

> [!NOTE]
> The ~3% gap is due to table and admonition content rendered differently by DITA-OT vs asciidoctor, `html2text` formatting variations between the two HTML outputs, and section title text consumed as structural markers (by design).

Run `scripts/compare-content.sh` to verify coverage after changes.

## AsciiDoc callout handling

<img width="500" alt="image" src="https://github.com/user-attachments/assets/631053ea-072e-436e-b273-f5e95a150627" />

## Known limitations

> [!NOTE]
> The pipeline produces a **fully resolved build** — all AsciiDoc attributes (`{ProductName}`, `{context}`, etc.), conditional directives (`ifdef`, `ifeval`), and `include::` reuse are expanded at build time by asciidoctor. The DITA output contains the rendered content, not the reusable source structure. AsciiDoc content reuse (shared modules included in multiple assemblies) is flattened into individual DITA topics. If required, reusable content (e.g. shared modules, common snippets) could be extracted and converted to DITA `conref` or `conkeyref` targets, but this is not currently implemented.

- Section title paragraphs ("Additional resources") in concept and reference topics remain as `<p>` text rather than being converted to `<section><title>`. They are structurally valid but semantically informal.
- Inline `<ph outputclass="db.title">` artifacts from dbdita are stripped (the text is typically a duplicate of the topic title).
- Definition lists (`<dl>`) pass through unchanged; no special handling is applied.
- Footnote references from deprecated `footnoteref` macros are not resolved.

## Local development

### Prerequisites

- **asciidoctor** (tested with 2.0.23)
- **Java 17+** (for Saxon) — install via:
  - Fedora/RHEL: `sudo dnf install java-17-openjdk`
  - Ubuntu/Debian: `sudo apt install openjdk-17-jdk`
- **Saxon HE 12.4** (included in `SaxonHE12-4J/`)
- **DITA-OT 4.3.1+** (for validation and HTML5 output)

### Getting started

```bash
# Install dependencies (requires Java 17+ already installed)
make install

# Full pipeline: AsciiDoc -> DocBook -> DITA -> HTML5
make clean all validate
```

### Make targets

| Target | Description |
|--------|-------------|
| `make install` | Install asciidoctor, html2text, and DITA-OT |
| `make all` | Run the full pipeline (stages 0-5 + images) |
| `make validate` | Build HTML5 output with DITA-OT to validate |
| `make stats` | Show topic type counts in specialized output |
| `make clean` | Remove `build/` and `out/` directories |
| `make manifest` | Stage 0 only |
| `make docbook` | Stage 1 only |
| `make enrich` | Stage 2 only |
| `make dita-raw` | Stage 3 only |
| `make specialize` | Stage 4 only |
| `make split` | Stage 5 only |
| `make images` | Copy images to output |

### Building the container image

```bash
docker build -t asciidoc-dita-pipe .
```

## Custom XSLT transforms

| File | Purpose |
|------|---------|
| `xsl/enrich-docbook.xsl` | Injects content-type metadata into DocBook |
| `xsl/specialize-topics.xsl` | Converts generic topics to concept/task/reference |
| `xsl/split-and-map.xsl` | Splits composite into files, generates ditamaps |

## Third-party tools

| Tool | Location | Purpose |
|------|----------|---------|
| Saxon HE 12.4 | `SaxonHE12-4J/` | XSLT 2.0 processor |
| dbdita | `dbdita/` | IBM DocBook-to-DITA transform (proof of concept) |

## License

This project is licensed under the [Apache License, Version 2.0](LICENSE).
