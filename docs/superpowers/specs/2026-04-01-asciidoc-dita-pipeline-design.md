# AsciiDoc to DITA 3.0 Pipeline Design

## Overview

Multi-stage pipeline to transform a modular AsciiDoc book (Red Hat-style with assemblies, concepts, procedures, references) into clean DITA 3.0 output with proper topic specialization, individual topic files, and a hierarchical ditamap structure.

## Source

- Entry point: `src/configuring-and-managing-networking/master.adoc`
- 298 AsciiDoc files: 51 assemblies, 29 concepts, 198 procedures, 20 references
- Files use `:_mod-docs-content-type: CONCEPT|PROCEDURE|REFERENCE|ASSEMBLY` markers
- File naming convention: `con_*.adoc`, `proc_*.adoc`, `ref_*.adoc`, `assembly_*.adoc`

## Pipeline Stages

```
src/**/*.adoc
    |
    v  [Stage 0] Python script scans .adoc files
build/content-type-manifest.xml
    |
    v  [Stage 1] asciidoctor -b docbook5
build/docbook/master.xml
    |
    v  [Stage 2] xsl/enrich-docbook.xsl (injects role attrs from manifest)
build/docbook/master-enriched.xml
    |
    v  [Stage 3] dbdita/db2dita/docbook2dita.xsl via Saxon
build/dita-raw/master-composite.dita
    |
    v  [Stage 4] xsl/specialize-topics.xsl
build/dita-specialized/master-composite.dita
    |
    v  [Stage 5] xsl/split-and-map.xsl (Saxon, generates multiple output files)
out/
  master.ditamap
  maps/assembly_*.ditamap
  topics/con_*.dita, proc_*.dita, ref_*.dita
  images/*.png
```

## Stage 0: Content-Type Manifest

Python script `scripts/build-manifest.py` scans all `.adoc` files:

1. Check for `:_mod-docs-content-type:` attribute (primary)
2. Fall back to filename prefix: `con_` -> concept, `proc_` -> task, `ref_` -> reference, `assembly_` -> assembly
3. Extract the section ID (the `[id="..."]` or derived from filename)
4. Output XML manifest mapping IDs to DITA topic types

```xml
<manifest>
  <entry id="con_how-wireguard-uses-tunnel-ips" type="concept" source="con_how-wireguard-uses-tunnel-ips.adoc"/>
  <entry id="proc_configuring-a-wireguard-server" type="task" source="proc_configuring-a-wireguard-server.adoc"/>
  <entry id="ref_protocols-used-by-wireguard" type="reference" source="ref_protocols-used-by-wireguard.adoc"/>
  <entry id="assembly_setting-up-a-wireguard-vpn" type="assembly" source="assembly_setting-up-a-wireguard-vpn.adoc"/>
</manifest>
```

## Stage 1: AsciiDoc to DocBook5

```
asciidoctor -b docbook5 src/configuring-and-managing-networking/master.adoc \
  -o build/docbook/master.xml
```

Produces ~1.1MB DocBook5 XML. Known issues:
- `footnoteref` deprecation warnings (non-blocking)
- Content-type info lost (addressed by Stage 2)

## Stage 2: Enrich DocBook

XSLT `xsl/enrich-docbook.xsl`:
- Reads `build/content-type-manifest.xml` as a parameter
- Identity transform with overrides for `<section>` elements
- Matches section `xml:id` against manifest entries
- Injects `role="concept|task|reference|assembly"` attribute

## Stage 3: dbdita Transform

```
java -jar SaxonHE12-4J/saxon-he-12.4.jar \
  -xsl:dbdita/db2dita/docbook2dita.xsl \
  -s:build/docbook/master-enriched.xml \
  -o:build/dita-raw/master-composite.dita
```

Produces composite DITA with all topics nested under `<dita>` root.
All topics are generic `<topic>` at this stage.

## Stage 4: Specialize and Clean Topics

XSLT `xsl/specialize-topics.xsl`:

### Topic specialization
- `<topic>` with `outputclass` containing role info -> `<concept>`, `<task>`, `<reference>`
- `<body>` -> `<conbody>`, `<taskbody>`, `<refbody>` accordingly
- ID prefix fallback: `con_*` -> concept, `proc_*` -> task, `ref_*` -> reference

### Task body restructuring
- Detect ordered lists (`<ol>`) inside task bodies
- Wrap in `<steps>` container
- Each `<li>` becomes `<step>` with `<cmd>` for first paragraph and `<info>` for rest
- Prerequisites section -> `<prereq>`
- Verification/result sections -> `<result>`

### Cleanup
- Remove all `outputclass="db.*"` attributes
- Remove empty XML comment placeholders (`<!-- topic/author not supplied -->` etc.)
- Fix image paths: ensure `href` points to `images/filename.png`
- Remove `xml:lang` from nested topics (only keep on root)
- Strip empty `<prolog>` and `<metadata>` elements

## Stage 5: Split and Generate Maps

XSLT `xsl/split-and-map.xsl` (uses `xsl:result-document`):

### Topic splitting
- Each specialized topic -> individual file in `out/topics/`
- Filename derived from topic ID: `{id}.dita`
- Add DITA 3.0 XML prolog and schema references

### Map generation
- `out/master.ditamap`: top-level bookmap-style ditamap
  - `<mapref>` to each assembly sub-map in `maps/`
  - Direct `<topicref>` for standalone modules included from master.adoc
- `out/maps/assembly_*.ditamap`: one per assembly
  - `<topicref>` entries for each child topic
  - Preserves nesting hierarchy from original assembly structure

### Image copying
- Handled by Makefile (cp/rsync), not XSLT

## Output Structure

```
out/
  master.ditamap
  maps/
    assembly_configuring-an-ethernet-connection.ditamap
    assembly_configuring-network-bonding.ditamap
    assembly_setting-up-a-wireguard-vpn.ditamap
    ... (51 assembly maps)
  topics/
    con_how-wireguard-uses-tunnel-ip-addresses.dita    (<concept>)
    proc_configuring-a-wireguard-server-by-using-nmcli.dita  (<task>)
    ref_protocols-and-primitives-used-by-wireguard.dita  (<reference>)
    ... (~250 topic files)
  images/
    *.png (54 images)
```

## Makefile

```makefile
SAXON = java -jar SaxonHE12-4J/saxon-he-12.4.jar
SRC = src/configuring-and-managing-networking

all: manifest docbook enrich dita-raw specialize split images

manifest:
	python3 scripts/build-manifest.py $(SRC) > build/content-type-manifest.xml

docbook:
	asciidoctor -b docbook5 $(SRC)/master.adoc -o build/docbook/master.xml

enrich:
	$(SAXON) -xsl:xsl/enrich-docbook.xsl -s:build/docbook/master.xml \
	  -o:build/docbook/master-enriched.xml manifest=build/content-type-manifest.xml

dita-raw:
	$(SAXON) -xsl:dbdita/db2dita/docbook2dita.xsl \
	  -s:build/docbook/master-enriched.xml -o:build/dita-raw/master-composite.dita

specialize:
	$(SAXON) -xsl:xsl/specialize-topics.xsl \
	  -s:build/dita-raw/master-composite.dita -o:build/dita-specialized/master-composite.dita

split:
	$(SAXON) -xsl:xsl/split-and-map.xsl \
	  -s:build/dita-specialized/master-composite.dita outdir=out

images:
	mkdir -p out/images
	cp $(SRC)/images/* $(SRC)/rhel-8/images/* out/images/ 2>/dev/null; true

validate:
	dita -i out/master.ditamap -f html5 -o out/html5

clean:
	rm -rf build/ out/
```

## DITA 3.0 Conformance

- Topic files use DITA 3.0 RNG-based schema references (no DTD)
- Specialized topic types: `<concept>`, `<task>`, `<reference>`
- Proper `<task>` structure: `<prereq>`, `<steps>/<step>/<cmd>`, `<result>`
- No legacy `outputclass` or DocBook artifacts
- Clean `id` attributes without context suffixes where possible

## Validation Strategy

- Run `dita -i out/master.ditamap -f html5 -o out/html5` after each iteration
- Target: zero ERROR lines from DITA-OT
- Warnings acceptable for first iteration, eliminate in subsequent passes

## Tools Required

- asciidoctor (installed: 2.0.23)
- Saxon HE 12.4 (present: SaxonHE12-4J/)
- DITA-OT 4.3.1 (installed at ~/bin/dita-ot-4.3.1/)
- Python 3 (for manifest script)
- dbdita (present: dbdita/)
