FROM docker.io/eclipse-temurin:17-jre-jammy

ARG DITA_OT_VERSION=4.3.1

# Install OS packages: ruby (for asciidoctor), python3, utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
        ruby ruby-dev \
        python3 \
        unzip curl ca-certificates \
        make \
    && rm -rf /var/lib/apt/lists/*

# Install asciidoctor
RUN gem install asciidoctor --no-document

# Install DITA-OT
RUN curl -sL "https://github.com/dita-ot/dita-ot/releases/download/${DITA_OT_VERSION}/dita-ot-${DITA_OT_VERSION}.zip" \
        -o /tmp/dita-ot.zip \
    && unzip -q /tmp/dita-ot.zip -d /usr/local/share \
    && ln -sf "/usr/local/share/dita-ot-${DITA_OT_VERSION}/bin/dita" /usr/local/bin/dita \
    && rm /tmp/dita-ot.zip

# Copy pipeline assets (XSLT, Saxon, dbdita, scripts, css)
WORKDIR /pipeline
COPY SaxonHE12-4J/ SaxonHE12-4J/
COPY dbdita/ dbdita/
COPY xsl/ xsl/
COPY scripts/ scripts/
COPY css/ css/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Working directories for build artifacts and output
RUN mkdir -p /input /output /work

WORKDIR /work

ENTRYPOINT ["/entrypoint.sh"]
