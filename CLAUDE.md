# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A 6-stage XSLT pipeline that transforms modular Red Hat-style AsciiDoc documentation into DITA 3.0 output with specialized topic types, hierarchical ditamaps, and zero DITA-OT validation errors. Uses IBM dbdita as the core DocBook-to-DITA converter, with custom XSLT stages before and after it.

## Build Commands

```bash
make clean all       # Full pipeline: stages 0-5 + images
make validate        # Build HTML5 with DITA-OT to verify zero errors
make stats           # Show topic type counts in specialized output
```

Individual stages (each depends on the previous):
```bash
make manifest        # Stage 0: scan .adoc files, build content-type manifest XML
make docbook         # Stage 1: asciidoctor -b docbook5
make enrich          # Stage 2: inject content-type roles into DocBook sections
make dita-raw        # Stage 3: dbdita DocBook-to-DITA transform
make specialize      # Stage 4: convert generic <topic> to concept/task/reference
make split           # Stage 5: split composite into individual files + ditamaps
make images          # Copy images to output
```

Content coverage check (compares DITA HTML5 output against direct asciidoctor output):
```bash
scripts/compare-content.sh
```

## Prerequisites

- **asciidoctor** (2.0.23+), **Java 17+**, **python3**
- **Saxon HE 12.4** — bundled in `SaxonHE12-4J/`, invoked as `java -jar SaxonHE12-4J/saxon-he-12.4.jar -dtd:off`
- **DITA-OT 4.3.1+** — `dita` must be on PATH for `make validate`
- **html2text** (pip) — for content coverage comparison only

## Pipeline Architecture

```
src/.../master.adoc
  → [Stage 0] scripts/build-manifest.py → build/content-type-manifest.xml
  → [Stage 1] asciidoctor -b docbook5   → build/docbook/master.xml
  → [Stage 2] xsl/enrich-docbook.xsl    → build/docbook/master-enriched.xml
  → [Stage 3] dbdita DocBook-to-DITA    → build/dita-raw/master-composite.dita
  → [Stage 4] xsl/specialize-topics.xsl → build/dita-specialized/master-composite.dita
  → [Stage 5] xsl/split-and-map.xsl     → out/{master.ditamap, topics/*.dita, maps/*.ditamap}
```

**Stage 0** (`scripts/build-manifest.py`): Scans `.adoc` files for `:_mod-docs-content-type:` attributes (CONCEPT/PROCEDURE/REFERENCE/ASSEMBLY) with filename prefix fallback (`con_`, `proc_`, `ref_`, `assembly_`). Outputs XML manifest mapping section IDs to DITA types.

**Stage 2** (`xsl/enrich-docbook.xsl`): Reads the manifest and injects `role="concept|task|reference|assembly"` onto DocBook `<section>` elements. Handles ID context-suffix stripping (DocBook IDs have `_assembly-context` suffixes that manifest IDs lack).

**Stage 4** (`xsl/specialize-topics.xsl`): The most complex transform. Converts generic `<topic>` to `<concept>`, `<task>`, or `<reference>` with proper body elements. For tasks, restructures flat content into DITA's strict task body model: `prereq → context → steps/steps-unordered → result → tasktroubleshooting → postreq`. Section titles are detected via `@outputclass='db.title'` (primary) with exact text match fallback — never `contains()` matching, which causes false positives.

**Stage 5** (`xsl/split-and-map.xsl`): Uses `xsl:result-document` to write individual topic files with correct DOCTYPE declarations. Generates a hierarchical `master.ditamap` with nested `<topicref>` elements matching the AsciiDoc assembly nesting, plus standalone sub-maps in `maps/`.

## Key Design Decisions

- **XSLT only for content transforms** — no Python post-processing of DITA output
- **Two-tier content type detection** — `:_mod-docs-content-type:` attribute first, filename prefix fallback
- **Section title detection uses `@outputclass='db.title'`** not `contains()` — prevents false positives like "The procedure below..." being matched as a Procedure section title
- **Reference `<refbody>` content model** — bare `<p>`, `<ul>`, `<ol>` are invalid; uses `for-each-group`/`group-adjacent` to wrap them in `<section>` elements
- **Task body element ordering** is enforced by the DITA content model: `prereq, context, steps, result, tasktroubleshooting, postreq` — the XSLT must emit them in this exact order
- **`<steps-unordered>`** is used for procedures with `<ul>` instead of `<ol>`
- **`<ph outputclass="db.title">`** artifacts from dbdita are stripped (template match suppresses them)

## CI

`.github/workflows/dita-transform.yml` runs the full pipeline on push to `main`, validates with DITA-OT, and force-pushes the `out/` contents to the `main_dita` branch.

## License

Apache 2.0 — matching the dbdita (IBM/DITA-OT) upstream license.
