<?xml version="1.0" encoding="UTF-8"?>
<!--
  Stage 5: Split composite DITA into individual topic files and generate ditamaps.
  Uses xsl:result-document to write multiple output files.
  Adds proper DOCTYPE declarations for DITA-OT processing.
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:f="urn:local:functions"
                version="2.0"
                exclude-result-prefixes="f">

  <xsl:param name="outdir" select="'out'"/>
  <xsl:param name="dita-version" select="'1.3'"/>

  <xsl:output method="xml" indent="yes" encoding="UTF-8"/>

  <!-- Cross-reference targets -->
  <xsl:key name="by-id" match="*[@id]" use="@id"/>

  <!-- Assemblies that get a sub-map: below the root topic, with children -->
  <xsl:key name="sub-maps" match="*[@outputclass = 'assembly'][not(parent::dita)][topic|concept|task|reference]" use="'yes'"/>

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

        <!-- Non-assembly root with body: the root has its own topic file -->
        <xsl:for-each select="(topic|concept|task|reference)[1][conbody/node() | taskbody/node() | refbody/node()]">
          <topicref href="{@id}.dita"/>
        </xsl:for-each>

        <!-- Process top-level topic's children (the book chapters/assemblies) -->
        <xsl:for-each select="(topic|concept|task|reference)[1]/(topic|concept|task|reference)">
          <xsl:call-template name="generate-topicref"/>
        </xsl:for-each>
      </map>
    </xsl:result-document>

    <!-- Generate sub-maps for assemblies only. master.ditamap covers the root and all other nesting. -->
    <xsl:for-each select="key('sub-maps', 'yes')">
      <xsl:call-template name="generate-sub-map"/>
    </xsl:for-each>

    <!-- Generate individual topic files (skip assembly topics — they are maps only) -->
    <xsl:apply-templates select="//(concept|task|reference)[@id]" mode="write-topic"/>

    <!-- Output a summary to the main result -->
    <pipeline-result>
      <xsl:attribute name="topics">
        <xsl:value-of select="count(//(concept|task|reference)[@id])"/>
      </xsl:attribute>
      <xsl:attribute name="maps">
        <xsl:value-of select="count(key('sub-maps', 'yes'))"/>
      </xsl:attribute>
    </pipeline-result>
  </xsl:template>

  <!-- Topics and maps share one folder, so a sub-map must not overwrite master.ditamap -->
  <xsl:function name="f:map-file">
    <xsl:param name="id"/>
    <xsl:sequence select="concat(if ($id = 'master') then 'master-submap' else $id, '.ditamap')"/>
  </xsl:function>

  <!-- Generate nested topicref entries (used in both master and sub-maps) -->
  <xsl:template name="generate-topicref">
    <topicref>
      <xsl:choose>
        <!-- Assemblies with children reference their sub-map; others reference the topic file -->
        <xsl:when test="@outputclass = 'assembly' and (topic|concept|task|reference)">
          <xsl:attribute name="href" select="f:map-file(@id)"/>
          <xsl:attribute name="format">ditamap</xsl:attribute>
        </xsl:when>
        <xsl:otherwise>
          <xsl:attribute name="href" select="concat(@id, '.dita')"/>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:call-template name="generate-child-topicrefs"/>
    </topicref>
  </xsl:template>

  <!-- Nest the topics of an assembly under its introduction, which has the ID of the assembly -->
  <xsl:template name="generate-child-topicrefs">
    <xsl:variable name="intro" select="concept[@id = current()/@id][current()/@outputclass = 'assembly']"/>
    <xsl:variable name="children" select="(topic|concept|task|reference) except $intro"/>
    <xsl:choose>
      <xsl:when test="$intro">
        <topicref href="{@id}.dita">
          <xsl:for-each select="$children">
            <xsl:call-template name="generate-topicref"/>
          </xsl:for-each>
        </topicref>
      </xsl:when>
      <xsl:otherwise>
        <xsl:for-each select="$children">
          <xsl:call-template name="generate-topicref"/>
        </xsl:for-each>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- Generate a standalone sub-map -->
  <xsl:template name="generate-sub-map">
    <xsl:result-document href="{$outdir}/{f:map-file(@id)}" method="xml" indent="yes" encoding="UTF-8"
                         doctype-public="{if ($dita-version = '1.3') then '-//OASIS//DTD DITA Map//EN' else ''}"
                         doctype-system="{if ($dita-version = '1.3') then 'map.dtd' else ''}">
      <xsl:if test="$dita-version = '2.0'">
        <xsl:processing-instruction name="xml-model">href="urn:pubid:oasis:names:tc:dita:rng:map.rng:2.0" schematypens="http://relaxng.org/ns/structure/1.0"</xsl:processing-instruction>
      </xsl:if>
      <map>
        <title><xsl:value-of select="title"/></title>
        <xsl:call-template name="generate-child-topicrefs"/>
      </map>
    </xsl:result-document>
  </xsl:template>

  <!-- Write individual topic files -->
  <xsl:template match="concept|task|reference" mode="write-topic">
    <xsl:variable name="element-name" select="local-name()"/>
    <xsl:variable name="filename" select="concat(@id, '.dita')"/>

    <!-- Determine DOCTYPE based on topic type -->
    <xsl:variable name="dt-public">
      <xsl:choose>
        <xsl:when test="$element-name = 'concept'">-//OASIS//DTD DITA Concept//EN</xsl:when>
        <xsl:when test="$element-name = 'task'">-//OASIS//DTD DITA Task//EN</xsl:when>
        <xsl:when test="$element-name = 'reference'">-//OASIS//DTD DITA Reference//EN</xsl:when>
      </xsl:choose>
    </xsl:variable>
    <xsl:variable name="dt-system">
      <xsl:choose>
        <xsl:when test="$element-name = 'concept'">concept.dtd</xsl:when>
        <xsl:when test="$element-name = 'task'">task.dtd</xsl:when>
        <xsl:when test="$element-name = 'reference'">reference.dtd</xsl:when>
      </xsl:choose>
    </xsl:variable>
    <!-- DITA 2.0 RNG schema URN per topic type -->
    <xsl:variable name="rng-urn">
      <xsl:choose>
        <xsl:when test="$element-name = 'concept'">urn:pubid:oasis:names:tc:dita:rng:concept.rng:2.0</xsl:when>
        <xsl:when test="$element-name = 'task'">urn:pubid:oasis:names:tc:dita:rng:task.rng:2.0</xsl:when>
        <xsl:when test="$element-name = 'reference'">urn:pubid:oasis:names:tc:dita:rng:reference.rng:2.0</xsl:when>
      </xsl:choose>
    </xsl:variable>

    <xsl:result-document href="{$outdir}/{$filename}" method="xml" indent="yes" encoding="UTF-8"
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

        <xsl:choose>
          <xsl:when test="not(title) or normalize-space(title) = ''">
            <title><xsl:value-of select="ancestor::*[self::topic|self::concept|self::task|self::reference][last()]/title"/></title>
          </xsl:when>
          <xsl:otherwise>
            <xsl:apply-templates select="title"/>
          </xsl:otherwise>
        </xsl:choose>

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
        </xsl:choose>

        <xsl:if test="related-links">
          <xsl:apply-templates select="related-links"/>
        </xsl:if>
      </xsl:element>
    </xsl:result-document>
  </xsl:template>

  <!--
    Cross-references within the composite use #id. Point them at the split files:
    - topic: id.dita
    - element in a topic: topic.dita#topic/id
    - assembly: first topic in the assembly, which is the introduction if there is one
  -->
  <xsl:template match="xref[starts-with(@href, '#')] | link[starts-with(@href, '#')]">
    <xsl:variable name="current-id" select="ancestor::*[self::topic or self::concept or self::task or self::reference][1]/@id"/>
    <xsl:variable name="target" select="key('by-id', tokenize(substring(@href, 2), '/')[last()])[1]"/>
    <xsl:variable name="owner" select="$target/ancestor-or-self::*[self::topic or self::concept or self::task or self::reference][1]"/>
    <xsl:variable name="topic" select="if ($owner/self::topic) then ($owner//(concept|task|reference))[1] else $owner"/>
    <xsl:variable name="element-id" select="if ($target is $owner or not($topic is $owner)) then () else $target/@id"/>
    <xsl:choose>
      <xsl:when test="$topic">
        <xsl:copy>
          <xsl:apply-templates select="@* except @href"/>
          <xsl:attribute name="href">
            <xsl:if test="$topic/@id != $current-id"><xsl:value-of select="concat($topic/@id, '.dita')"/></xsl:if>
            <xsl:if test="$topic/@id = $current-id or $element-id">
              <xsl:value-of select="concat('#', string-join(($topic/@id, $element-id), '/'))"/>
            </xsl:if>
          </xsl:attribute>
          <xsl:apply-templates select="node()"/>
          <!-- Without link text, DITA-OT shows the title of the first topic instead of the assembly -->
          <xsl:if test="self::xref and not(normalize-space(.)) and not($topic is $owner)">
            <xsl:value-of select="normalize-space($owner/title)"/>
          </xsl:if>
        </xsl:copy>
      </xsl:when>
      <xsl:otherwise>
        <!-- Keep the text, drop the broken link -->
        <xsl:message>
          <xsl:text>WARNING: Cross-reference "</xsl:text>
          <xsl:value-of select="@href"/>
          <xsl:text>" in topic "</xsl:text>
          <xsl:value-of select="$current-id"/>
          <xsl:text>" has no target in this build. Keeping the text without a link.</xsl:text>
        </xsl:message>
        <xsl:if test="self::xref"><xsl:apply-templates select="node()"/></xsl:if>
      </xsl:otherwise>
    </xsl:choose>
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
