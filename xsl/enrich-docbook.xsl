<?xml version="1.0" encoding="UTF-8"?>
<!--
  Stage 2: Enrich DocBook with content-type information from manifest.
  Injects role="concept|task|reference|assembly" onto matching <section> elements.

  Matching strategy:
  1. DocBook xml:id has context suffixes (e.g., "con_foo_assembly-context")
  2. Manifest has base IDs (e.g., "con_foo")
  3. We strip context suffix and try multiple match variations
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:d="http://docbook.org/ns/docbook"
                xmlns:xl="http://www.w3.org/1999/xlink"
                version="2.0"
                exclude-result-prefixes="d">

  <xsl:param name="manifest-uri" select="''"/>

  <xsl:variable name="manifest-doc" select="if ($manifest-uri != '') then document($manifest-uri) else ()"/>

  <xsl:output method="xml" indent="no" encoding="UTF-8"/>

  <!-- Identity transform -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Key for manifest lookup -->
  <xsl:key name="manifest-by-id" match="entry" use="@id"/>

  <!-- Match sections and prefaces, inject role from manifest -->
  <xsl:template match="d:section[@xml:id] | d:preface[@xml:id] | d:simplesect[@xml:id]">
    <xsl:variable name="full-id" select="string(@xml:id)"/>

    <!-- Strip context suffix: the part after the last underscore that looks like a context
         Context suffixes are like _configuring-and-managing-networking or _assembly-name
         The base ID is the part that matches the manifest entry -->

    <!-- Try progressively shorter ID by stripping _suffix segments -->
    <xsl:variable name="detected-type">
      <xsl:choose>
        <!-- Direct match on full ID -->
        <xsl:when test="$manifest-doc and key('manifest-by-id', $full-id, $manifest-doc)">
          <xsl:value-of select="key('manifest-by-id', $full-id, $manifest-doc)/@type"/>
        </xsl:when>

        <!-- Strip one context suffix (everything after last _word-with-hyphens) -->
        <xsl:when test="$manifest-doc and contains($full-id, '_')">
          <xsl:variable name="stripped1" select="replace($full-id, '_[a-z][a-z0-9-]*$', '')"/>
          <xsl:choose>
            <xsl:when test="key('manifest-by-id', $stripped1, $manifest-doc)">
              <xsl:value-of select="key('manifest-by-id', $stripped1, $manifest-doc)/@type"/>
            </xsl:when>
            <!-- Strip two context suffixes -->
            <xsl:when test="contains($stripped1, '_')">
              <xsl:variable name="stripped2" select="replace($stripped1, '_[a-z][a-z0-9-]*$', '')"/>
              <xsl:choose>
                <xsl:when test="key('manifest-by-id', $stripped2, $manifest-doc)">
                  <xsl:value-of select="key('manifest-by-id', $stripped2, $manifest-doc)/@type"/>
                </xsl:when>
                <xsl:otherwise/>
              </xsl:choose>
            </xsl:when>
            <xsl:otherwise/>
          </xsl:choose>
        </xsl:when>
        <xsl:otherwise/>
      </xsl:choose>
    </xsl:variable>

    <!-- Final type: use manifest match, or fall back to ID prefix -->
    <xsl:variable name="final-type">
      <xsl:choose>
        <xsl:when test="$detected-type != ''">
          <xsl:value-of select="$detected-type"/>
        </xsl:when>
        <xsl:when test="starts-with($full-id, 'con_')">concept</xsl:when>
        <xsl:when test="starts-with($full-id, 'proc_')">task</xsl:when>
        <xsl:when test="starts-with($full-id, 'ref_')">reference</xsl:when>
        <xsl:when test="starts-with($full-id, 'assembly_')">assembly</xsl:when>
        <xsl:otherwise>topic</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:attribute name="role">
        <xsl:value-of select="$final-type"/>
      </xsl:attribute>
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>
