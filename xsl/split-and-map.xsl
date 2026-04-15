<?xml version="1.0" encoding="UTF-8"?>
<!--
  Stage 5: Split composite DITA into individual topic files and generate ditamaps.
  Uses xsl:result-document to write multiple output files.
  Adds proper DOCTYPE declarations for DITA-OT processing.
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                version="2.0">

  <xsl:param name="outdir" select="'out'"/>
  <xsl:param name="dita-version" select="'1.3'"/>

  <xsl:output method="xml" indent="yes" encoding="UTF-8"/>

  <!-- Root template: generate master.ditamap -->
  <xsl:template match="/dita">
    <!-- Generate master.ditamap -->
    <xsl:result-document href="{$outdir}/master.ditamap" method="xml" indent="yes" encoding="UTF-8"
                         doctype-public="{if ($dita-version = '1.3') then '-//OASIS//DTD DITA Map//EN' else ''}"
                         doctype-system="{if ($dita-version = '1.3') then 'map.dtd' else ''}">
      <xsl:if test="$dita-version = '2.0'">
        <xsl:processing-instruction name="xml-model">href="urn:pubid:oasis:names:tc:dita:rng:map.rng:2.0" schematypens="http://relaxng.org/ns/structure/1.0"</xsl:processing-instruction>
      </xsl:if>
      <map>
        <title>
          <xsl:value-of select="(topic|concept|task|reference)[1]/title"/>
        </title>

        <!-- Process top-level topic's children (the book chapters/assemblies) -->
        <xsl:for-each select="(topic|concept|task|reference)[1]/(topic|concept|task|reference)">
          <xsl:call-template name="generate-topicref"/>
        </xsl:for-each>
      </map>
    </xsl:result-document>

    <!-- Generate individual topic files -->
    <xsl:apply-templates select="//(topic|concept|task|reference)[@id]" mode="write-topic"/>

    <!-- Output a summary to the main result -->
    <pipeline-result>
      <xsl:attribute name="topics">
        <xsl:value-of select="count(//(topic|concept|task|reference)[@id])"/>
      </xsl:attribute>
      <xsl:attribute name="maps">
        <xsl:value-of select="count((topic|concept|task|reference)[1]/(topic|concept|task|reference)[topic|concept|task|reference])"/>
      </xsl:attribute>
    </pipeline-result>
  </xsl:template>

  <!-- Generate nested topicref entries in master map, plus sub-maps for assemblies -->
  <xsl:template name="generate-topicref">
    <xsl:choose>
      <!-- Assembly: has child topics -> nested topicrefs + sub-map -->
      <xsl:when test="(topic|concept|task|reference)">
        <!-- Nested topicref in master map -->
        <topicref href="topics/{@id}.dita">
          <xsl:for-each select="(topic|concept|task|reference)">
            <xsl:call-template name="generate-topicref-nested">
              <xsl:with-param name="path-prefix" select="'topics/'"/>
            </xsl:call-template>
          </xsl:for-each>
        </topicref>

        <!-- Also generate a standalone sub-map for convenience -->
        <xsl:variable name="map-filename" select="concat(@id, '.ditamap')"/>
        <xsl:result-document href="{$outdir}/maps/{$map-filename}" method="xml" indent="yes" encoding="UTF-8"
                             doctype-public="{if ($dita-version = '1.3') then '-//OASIS//DTD DITA Map//EN' else ''}"
                             doctype-system="{if ($dita-version = '1.3') then 'map.dtd' else ''}">
          <xsl:if test="$dita-version = '2.0'">
            <xsl:processing-instruction name="xml-model">href="urn:pubid:oasis:names:tc:dita:rng:map.rng:2.0" schematypens="http://relaxng.org/ns/structure/1.0"</xsl:processing-instruction>
          </xsl:if>
          <map>
            <title><xsl:value-of select="title"/></title>
            <xsl:if test="body/node() | conbody/node() | taskbody/node() | refbody/node()">
              <topicref href="../topics/{@id}.dita"/>
            </xsl:if>
            <xsl:for-each select="(topic|concept|task|reference)">
              <xsl:call-template name="generate-topicref-nested">
                <xsl:with-param name="path-prefix" select="'../topics/'"/>
              </xsl:call-template>
            </xsl:for-each>
          </map>
        </xsl:result-document>
      </xsl:when>

      <!-- Standalone topic: direct topicref -->
      <xsl:otherwise>
        <topicref href="topics/{@id}.dita"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- Recursive helper for nested topicrefs (used in both master and sub-maps) -->
  <xsl:template name="generate-topicref-nested">
    <xsl:param name="path-prefix"/>
    <xsl:choose>
      <xsl:when test="(topic|concept|task|reference)">
        <topicref href="{$path-prefix}{@id}.dita">
          <xsl:for-each select="(topic|concept|task|reference)">
            <xsl:call-template name="generate-topicref-nested">
              <xsl:with-param name="path-prefix" select="$path-prefix"/>
            </xsl:call-template>
          </xsl:for-each>
        </topicref>
      </xsl:when>
      <xsl:otherwise>
        <topicref href="{$path-prefix}{@id}.dita"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- Write individual topic files -->
  <xsl:template match="topic|concept|task|reference" mode="write-topic">
    <xsl:variable name="element-name" select="local-name()"/>
    <xsl:variable name="filename" select="concat(@id, '.dita')"/>

    <!-- Determine DOCTYPE based on topic type -->
    <xsl:variable name="dt-public">
      <xsl:choose>
        <xsl:when test="$element-name = 'concept'">-//OASIS//DTD DITA Concept//EN</xsl:when>
        <xsl:when test="$element-name = 'task'">-//OASIS//DTD DITA Task//EN</xsl:when>
        <xsl:when test="$element-name = 'reference'">-//OASIS//DTD DITA Reference//EN</xsl:when>
        <xsl:otherwise>-//OASIS//DTD DITA Topic//EN</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:variable name="dt-system">
      <xsl:choose>
        <xsl:when test="$element-name = 'concept'">concept.dtd</xsl:when>
        <xsl:when test="$element-name = 'task'">task.dtd</xsl:when>
        <xsl:when test="$element-name = 'reference'">reference.dtd</xsl:when>
        <xsl:otherwise>topic.dtd</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <!-- DITA 2.0 RNG schema URN per topic type -->
    <xsl:variable name="rng-urn">
      <xsl:choose>
        <xsl:when test="$element-name = 'concept'">urn:pubid:oasis:names:tc:dita:rng:concept.rng:2.0</xsl:when>
        <xsl:when test="$element-name = 'task'">urn:pubid:oasis:names:tc:dita:rng:task.rng:2.0</xsl:when>
        <xsl:when test="$element-name = 'reference'">urn:pubid:oasis:names:tc:dita:rng:reference.rng:2.0</xsl:when>
        <xsl:otherwise>urn:pubid:oasis:names:tc:dita:rng:topic.rng:2.0</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:result-document href="{$outdir}/topics/{$filename}" method="xml" indent="yes" encoding="UTF-8"
                         doctype-public="{if ($dita-version = '1.3') then $dt-public else ''}"
                         doctype-system="{if ($dita-version = '1.3') then $dt-system else ''}">
      <xsl:if test="$dita-version = '2.0'">
        <xsl:processing-instruction name="xml-model">href="<xsl:value-of select="$rng-urn"/>" schematypens="http://relaxng.org/ns/structure/1.0"</xsl:processing-instruction>
      </xsl:if>
      <xsl:element name="{$element-name}">
        <xsl:attribute name="id"><xsl:value-of select="@id"/></xsl:attribute>
        <xsl:if test="@xml:lang">
          <xsl:attribute name="xml:lang"><xsl:value-of select="@xml:lang"/></xsl:attribute>
        </xsl:if>

        <xsl:apply-templates select="title"/>

        <xsl:if test="shortdesc">
          <xsl:apply-templates select="shortdesc"/>
        </xsl:if>

        <!-- Body content based on topic type -->
        <xsl:choose>
          <xsl:when test="$element-name = 'concept' and conbody">
            <xsl:apply-templates select="conbody"/>
          </xsl:when>
          <xsl:when test="$element-name = 'task' and taskbody">
            <xsl:apply-templates select="taskbody"/>
          </xsl:when>
          <xsl:when test="$element-name = 'reference' and refbody">
            <xsl:apply-templates select="refbody"/>
          </xsl:when>
          <xsl:when test="body">
            <body>
              <xsl:apply-templates select="body/node()"/>
            </body>
          </xsl:when>
        </xsl:choose>

        <xsl:if test="related-links">
          <xsl:apply-templates select="related-links"/>
        </xsl:if>
      </xsl:element>
    </xsl:result-document>
  </xsl:template>

  <!-- Identity transform for content within topics -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Strip outputclass attributes, but keep language-* on codeblocks -->
  <xsl:template match="@outputclass[not(starts-with(., 'language-'))]"/>

</xsl:stylesheet>
