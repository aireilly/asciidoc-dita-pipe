SAXON = java -jar SaxonHE12-4J/saxon-he-12.4.jar -dtd:off
SRC = src/configuring-and-managing-networking
BUILD = build
OUT = out

.PHONY: all manifest docbook enrich dita-raw specialize split images validate clean

all: manifest docbook enrich dita-raw specialize split images

manifest: $(BUILD)/content-type-manifest.xml

$(BUILD)/content-type-manifest.xml: $(shell find $(SRC) -name '*.adoc' 2>/dev/null)
	@mkdir -p $(BUILD)
	python3 scripts/build-manifest.py $(SRC) > $@
	@echo "== Manifest: $$(grep -c '<entry' $@) entries"

docbook: $(BUILD)/docbook/master.xml

$(BUILD)/docbook/master.xml: $(shell find $(SRC) -name '*.adoc' 2>/dev/null)
	@mkdir -p $(BUILD)/docbook
	cd $(SRC) && asciidoctor -b docbook5 master.adoc -o ../../$@
	@echo "== DocBook: $$(ls -lh $@ | awk '{print $$5}')"

enrich: $(BUILD)/docbook/master-enriched.xml

$(BUILD)/docbook/master-enriched.xml: $(BUILD)/docbook/master.xml $(BUILD)/content-type-manifest.xml xsl/enrich-docbook.xsl
	$(SAXON) -xsl:xsl/enrich-docbook.xsl \
		-s:$(BUILD)/docbook/master.xml \
		-o:$@ \
		manifest-uri=$(CURDIR)/$(BUILD)/content-type-manifest.xml
	@echo "== Enriched DocBook: $$(ls -lh $@ | awk '{print $$5}')"

dita-raw: $(BUILD)/dita-raw/master-composite.dita

$(BUILD)/dita-raw/master-composite.dita: $(BUILD)/docbook/master-enriched.xml
	@mkdir -p $(BUILD)/dita-raw
	$(SAXON) -xsl:dbdita/db2dita/docbook2dita.xsl \
		-s:$(BUILD)/docbook/master-enriched.xml \
		-o:$@
	@echo "== Raw DITA: $$(ls -lh $@ | awk '{print $$5}')"

specialize: $(BUILD)/dita-specialized/master-composite.dita

$(BUILD)/dita-specialized/master-composite.dita: $(BUILD)/dita-raw/master-composite.dita xsl/specialize-topics.xsl
	@mkdir -p $(BUILD)/dita-specialized
	sed '/DOCTYPE/,/>/d' $(BUILD)/dita-raw/master-composite.dita > $(BUILD)/dita-raw/master-composite-nodtd.dita
	$(SAXON) -xsl:xsl/specialize-topics.xsl \
		-s:$(BUILD)/dita-raw/master-composite-nodtd.dita \
		-o:$@
	@echo "== Specialized DITA: $$(ls -lh $@ | awk '{print $$5}')"

split: $(BUILD)/dita-specialized/master-composite.dita xsl/split-and-map.xsl
	@mkdir -p $(OUT)/topics $(OUT)/maps
	$(SAXON) -xsl:xsl/split-and-map.xsl \
		-s:$(BUILD)/dita-specialized/master-composite.dita \
		-o:$(BUILD)/split-result.xml \
		outdir=file:///$(CURDIR)/$(OUT)
	@echo "== Split: $$(find $(OUT)/topics -name '*.dita' | wc -l) topics, $$(find $(OUT)/maps -name '*.ditamap' | wc -l) maps"

images:
	@mkdir -p $(OUT)/images
	@cp $(SRC)/images/* $(OUT)/images/ 2>/dev/null; true
	@cp $(SRC)/rhel-8/images/* $(OUT)/images/ 2>/dev/null; true
	@echo "== Images: $$(ls $(OUT)/images/ | wc -l) files copied"

validate:
	dita -i $(OUT)/master.ditamap -f html5 -o $(OUT)/html5 \
		-Dargs.cssroot=$(CURDIR)/css -Dargs.css=custom.css -Dargs.copycss=yes

clean:
	rm -rf $(BUILD) $(OUT)

# Quick check: count topics by type in the specialized composite
stats:
	@echo "=== Topic counts in specialized output ==="
	@echo "  concept: $$(grep -c '<concept ' $(BUILD)/dita-specialized/master-composite.dita 2>/dev/null || echo 0)"
	@echo "  task:    $$(grep -c '<task ' $(BUILD)/dita-specialized/master-composite.dita 2>/dev/null || echo 0)"
	@echo "  reference: $$(grep -c '<reference ' $(BUILD)/dita-specialized/master-composite.dita 2>/dev/null || echo 0)"
	@echo "  topic:   $$(grep -c '<topic ' $(BUILD)/dita-specialized/master-composite.dita 2>/dev/null || echo 0)"
