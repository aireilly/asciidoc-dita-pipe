<?xml version="1.0" encoding="UTF-8"?>
<!--
  Stage 4: Specialize generic <topic> elements into <concept>, <task>, <reference>
  based on outputclass role info and ID prefix fallback.
  Also cleans up dbdita artifacts.
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                version="2.0">

  <xsl:output method="xml" indent="yes" encoding="UTF-8"
              omit-xml-declaration="no"/>

  <xsl:strip-space elements="*"/>

  <!-- Root: pass through the <dita> wrapper -->
  <xsl:template match="/dita">
    <dita>
      <xsl:apply-templates/>
    </dita>
  </xsl:template>

  <!-- Main topic transformation -->
  <xsl:template match="topic">
    <xsl:variable name="type">
      <xsl:choose>
        <!-- Primary: outputclass from enriched DocBook role -->
        <xsl:when test="@outputclass = 'concept'">concept</xsl:when>
        <xsl:when test="@outputclass = 'task'">task</xsl:when>
        <xsl:when test="@outputclass = 'reference'">reference</xsl:when>
        <!-- Fallback: ID prefix -->
        <xsl:when test="starts-with(@id, 'con_')">concept</xsl:when>
        <xsl:when test="starts-with(@id, 'proc_')">task</xsl:when>
        <xsl:when test="starts-with(@id, 'ref_')">reference</xsl:when>
        <xsl:otherwise>topic</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:choose>
      <xsl:when test="$type = 'concept'">
        <concept id="{@id}">
          <xsl:call-template name="copy-topic-attrs"/>
          <xsl:apply-templates select="title"/>
          <xsl:apply-templates select="shortdesc"/>
          <xsl:if test="body/node()">
            <conbody>
              <xsl:apply-templates select="body/node()"/>
            </conbody>
          </xsl:if>
          <xsl:apply-templates select="related-links[.//text()[normalize-space()]]"/>
          <xsl:apply-templates select="topic"/>
        </concept>
      </xsl:when>

      <xsl:when test="$type = 'task'">
        <task id="{@id}">
          <xsl:call-template name="copy-topic-attrs"/>
          <xsl:apply-templates select="title"/>
          <xsl:apply-templates select="shortdesc"/>
          <taskbody>
            <xsl:call-template name="build-task-body">
              <xsl:with-param name="body" select="body"/>
            </xsl:call-template>
          </taskbody>
          <xsl:apply-templates select="related-links[.//text()[normalize-space()]]"/>
          <xsl:apply-templates select="topic"/>
        </task>
      </xsl:when>

      <xsl:when test="$type = 'reference'">
        <reference id="{@id}">
          <xsl:call-template name="copy-topic-attrs"/>
          <xsl:apply-templates select="title"/>
          <xsl:apply-templates select="shortdesc"/>
          <xsl:if test="body/node()">
            <refbody>
              <xsl:call-template name="build-ref-body">
                <xsl:with-param name="body" select="body"/>
              </xsl:call-template>
            </refbody>
          </xsl:if>
          <xsl:apply-templates select="related-links[.//text()[normalize-space()]]"/>
          <xsl:apply-templates select="topic"/>
        </reference>
      </xsl:when>

      <xsl:otherwise>
        <!-- Keep as generic topic -->
        <topic id="{@id}">
          <xsl:call-template name="copy-topic-attrs"/>
          <xsl:apply-templates select="title"/>
          <xsl:apply-templates select="shortdesc"/>
          <xsl:if test="body/node()">
            <body>
              <xsl:apply-templates select="body/node()"/>
            </body>
          </xsl:if>
          <xsl:apply-templates select="related-links[.//text()[normalize-space()]]"/>
          <xsl:apply-templates select="topic"/>
        </topic>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- Copy non-db.* attributes -->
  <xsl:template name="copy-topic-attrs">
    <!-- Only keep xml:lang on top-level topic -->
    <xsl:if test="not(parent::topic) and @xml:lang">
      <xsl:attribute name="xml:lang"><xsl:value-of select="@xml:lang"/></xsl:attribute>
    </xsl:if>
  </xsl:template>

  <!--
    Build task body following DITA content model:
    (prereq?, context?, (steps|steps-unordered)?, result?, tasktroubleshooting?, example?, postreq?)

    Strategy: Use for-each-group to process ALL body children sequentially.
    Group by detected section type based on title paragraphs.
    Collect into DITA-ordered buckets, then emit in correct order.
    No content is dropped.
  -->
  <xsl:template name="build-task-body">
    <xsl:param name="body"/>

    <xsl:variable name="children" select="$body/*"/>


    <!--
      Walk all children in order, assign to sections based on
      the most recent section title encountered. Emit everything.
    -->

    <!-- Detect section titles using db.title outputclass (primary) or exact text match (fallback) -->
    <xsl:variable name="prereq-titles" select="$children[self::p
      and ((@outputclass = 'db.title' and (normalize-space(.) = 'Prerequisites' or normalize-space(.) = 'Prerequisite'))
           or (not(@outputclass = 'db.title') and string-length(normalize-space(.)) &lt; 30
               and (normalize-space(lower-case(.)) = 'prerequisites' or normalize-space(lower-case(.)) = 'prerequisite')))]"/>

    <xsl:variable name="procedure-titles" select="$children[self::p
      and ((@outputclass = 'db.title' and normalize-space(.) = 'Procedure')
           or (not(@outputclass = 'db.title') and string-length(normalize-space(.)) &lt; 20
               and normalize-space(lower-case(.)) = 'procedure'))]"/>

    <xsl:variable name="verification-titles" select="$children[self::p
      and ((@outputclass = 'db.title' and normalize-space(.) = 'Verification')
           or (not(@outputclass = 'db.title') and string-length(normalize-space(.)) &lt; 20
               and normalize-space(lower-case(.)) = 'verification'))]"/>

    <xsl:variable name="resources-titles" select="$children[self::p
      and ((@outputclass = 'db.title' and (normalize-space(.) = 'Additional resources' or normalize-space(.) = 'Next steps'))
           or (not(@outputclass = 'db.title') and string-length(normalize-space(.)) &lt; 30
               and (normalize-space(lower-case(.)) = 'additional resources' or normalize-space(lower-case(.)) = 'next steps')))]"/>

    <xsl:variable name="troubleshooting-titles" select="$children[self::p
      and ((@outputclass = 'db.title' and (normalize-space(.) = 'Troubleshooting' or normalize-space(.) = 'Troubleshooting steps'))
           or (not(@outputclass = 'db.title') and string-length(normalize-space(.)) &lt; 30
               and (normalize-space(lower-case(.)) = 'troubleshooting' or normalize-space(lower-case(.)) = 'troubleshooting steps')))]"/>

    <!-- All section titles combined -->
    <xsl:variable name="all-section-titles" select="$prereq-titles | $procedure-titles | $verification-titles | $resources-titles | $troubleshooting-titles"/>

    <!-- All section title positions -->
    <xsl:variable name="all-title-positions">
      <xsl:for-each select="$prereq-titles | $procedure-titles | $verification-titles | $resources-titles | $troubleshooting-titles">
        <xsl:value-of select="count(preceding-sibling::*) + 1"/>
        <xsl:text>,</xsl:text>
      </xsl:for-each>
    </xsl:variable>

    <!-- PREREQ: emit first -->
    <xsl:if test="$prereq-titles">
      <prereq>
        <xsl:call-template name="emit-section-content">
          <xsl:with-param name="title-node" select="$prereq-titles[1]"/>
          <xsl:with-param name="children" select="$children"/>
        </xsl:call-template>
      </prereq>
    </xsl:if>

    <!-- CONTEXT: everything before first section title (or first ol if no titles) -->
    <xsl:variable name="first-title-pos">
      <xsl:choose>
        <xsl:when test="$prereq-titles | $procedure-titles | $verification-titles | $resources-titles | $troubleshooting-titles">
          <xsl:for-each select="($prereq-titles | $procedure-titles | $verification-titles | $resources-titles | $troubleshooting-titles)">
            <xsl:sort select="count(preceding-sibling::*)" data-type="number"/>
            <xsl:if test="position() = 1">
              <xsl:value-of select="count(preceding-sibling::*) + 1"/>
            </xsl:if>
          </xsl:for-each>
        </xsl:when>
        <xsl:when test="$children[self::ol]">
          <xsl:value-of select="count($children[self::ol][1]/preceding-sibling::*) + 1"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="count($children) + 1"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:variable name="context-nodes" select="$children[position() &lt; number($first-title-pos)]"/>
    <xsl:if test="$context-nodes">
      <context>
        <xsl:apply-templates select="$context-nodes"/>
      </context>
    </xsl:if>



    <!-- STEPS: ol/ul after Procedure title, or first ol if no section titles exist -->
    <xsl:variable name="steps-source">
      <xsl:choose>
        <xsl:when test="$procedure-titles">
          <xsl:copy-of select="$procedure-titles[1]/following-sibling::*[1][self::ol or self::ul]"/>
        </xsl:when>
        <xsl:when test="not($prereq-titles) and not($procedure-titles) and not($verification-titles) and $children[self::ol]">
          <xsl:copy-of select="$children[self::ol][1]"/>
        </xsl:when>
      </xsl:choose>
    </xsl:variable>

    <xsl:variable name="steps-list" select="($steps-source/ol | $steps-source/ul)[1]"/>

    <xsl:if test="$steps-list">
      <xsl:variable name="steps-element-name">
        <xsl:choose>
          <xsl:when test="$steps-source/ol">steps</xsl:when>
          <xsl:otherwise>steps-unordered</xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:element name="{$steps-element-name}">
        <xsl:for-each select="$steps-list/li">
          <step>
            <cmd>
              <xsl:choose>
                <xsl:when test="p">
                  <xsl:apply-templates select="p[1]/node()"/>
                </xsl:when>
                <xsl:otherwise>
                  <xsl:apply-templates select="node()"/>
                </xsl:otherwise>
              </xsl:choose>
            </cmd>
            <xsl:if test="p[position() > 1] or *[not(self::p)]">
              <info>
                <xsl:apply-templates select="p[position() > 1] | *[not(self::p)]"/>
              </info>
            </xsl:if>
          </step>
        </xsl:for-each>
      </xsl:element>
    </xsl:if>

    <!-- RESULT: content after Verification title, plus any uncategorized content after steps -->
    <xsl:variable name="has-verification-content" select="$verification-titles"/>
    <xsl:variable name="has-remaining-content">
      <xsl:if test="$procedure-titles">
        <xsl:variable name="proc-ol" select="$procedure-titles[1]/following-sibling::*[1][self::ol]"/>
        <xsl:if test="$proc-ol">
          <xsl:variable name="after-steps" select="$proc-ol/following-sibling::*[
            not(. = $verification-titles or . = $resources-titles)
            and not(. = $all-section-titles)
            and (not($verification-titles) or count(preceding-sibling::*) &lt; count($verification-titles[1]/preceding-sibling::*))
            and (not($resources-titles) or count(preceding-sibling::*) &lt; count($resources-titles[1]/preceding-sibling::*))
          ]"/>
          <xsl:if test="$after-steps">yes</xsl:if>
        </xsl:if>
      </xsl:if>
    </xsl:variable>

    <xsl:if test="$has-verification-content or $has-remaining-content = 'yes'">
      <result>
        <!-- Uncategorized content after steps but before verification/resources -->
        <xsl:if test="$procedure-titles">
          <xsl:variable name="proc-ol" select="$procedure-titles[1]/following-sibling::*[1][self::ol]"/>
          <xsl:if test="$proc-ol">
            <xsl:apply-templates select="$proc-ol/following-sibling::*[
              not(. = $verification-titles or . = $resources-titles)
              and not(. = $all-section-titles)
              and (not($verification-titles) or count(preceding-sibling::*) &lt; count($verification-titles[1]/preceding-sibling::*))
              and (not($resources-titles) or count(preceding-sibling::*) &lt; count($resources-titles[1]/preceding-sibling::*))
            ]"/>
          </xsl:if>
        </xsl:if>
        <!-- Verification section content -->
        <xsl:if test="$verification-titles">
          <xsl:call-template name="emit-section-content">
            <xsl:with-param name="title-node" select="$verification-titles[1]"/>
            <xsl:with-param name="children" select="$children"/>
          </xsl:call-template>
        </xsl:if>
      </result>
    </xsl:if>

    <!-- TASKTROUBLESHOOTING: content after Troubleshooting title -->
    <xsl:if test="$troubleshooting-titles">
      <tasktroubleshooting>
        <xsl:call-template name="emit-section-content">
          <xsl:with-param name="title-node" select="$troubleshooting-titles[1]"/>
          <xsl:with-param name="children" select="$children"/>
        </xsl:call-template>
      </tasktroubleshooting>
    </xsl:if>

    <!-- POSTREQ: content after Additional resources / Next steps title -->
    <xsl:if test="$resources-titles">
      <postreq>
        <xsl:call-template name="emit-section-content">
          <xsl:with-param name="title-node" select="$resources-titles[1]"/>
          <xsl:with-param name="children" select="$children"/>
        </xsl:call-template>
      </postreq>
    </xsl:if>

    <!-- FALLBACK: if nothing was matched, wrap everything in context -->
    <xsl:if test="not($context-nodes) and not($prereq-titles) and not($steps-list) and not($verification-titles) and not($resources-titles) and not($troubleshooting-titles) and $children">
      <context>
        <xsl:apply-templates select="$children"/>
      </context>
    </xsl:if>

  </xsl:template>

  <!-- Helper: emit content between a section title and the next section title -->
  <xsl:template name="emit-section-content">
    <xsl:param name="title-node"/>
    <xsl:param name="children"/>

    <!-- All section titles for boundary detection (using db.title outputclass or exact text match) -->
    <xsl:variable name="all-titles" select="$children[self::p
      and ((@outputclass = 'db.title' and (normalize-space(.) = 'Prerequisites' or normalize-space(.) = 'Prerequisite'
           or normalize-space(.) = 'Procedure' or normalize-space(.) = 'Verification'
           or normalize-space(.) = 'Additional resources' or normalize-space(.) = 'Next steps'
           or normalize-space(.) = 'Troubleshooting' or normalize-space(.) = 'Troubleshooting steps'))
           or (not(@outputclass = 'db.title') and string-length(normalize-space(.)) &lt; 30
               and (normalize-space(lower-case(.)) = 'prerequisites' or normalize-space(lower-case(.)) = 'prerequisite'
                    or normalize-space(lower-case(.)) = 'procedure' or normalize-space(lower-case(.)) = 'verification'
                    or normalize-space(lower-case(.)) = 'additional resources' or normalize-space(lower-case(.)) = 'next steps'
                    or normalize-space(lower-case(.)) = 'troubleshooting' or normalize-space(lower-case(.)) = 'troubleshooting steps')))]"/>

    <xsl:variable name="title-pos" select="count($title-node/preceding-sibling::*) + 1"/>

    <!-- Find next title after this one -->
    <xsl:variable name="next-title" select="$all-titles[count(preceding-sibling::*) + 1 > $title-pos][1]"/>
    <xsl:variable name="next-title-pos">
      <xsl:choose>
        <xsl:when test="$next-title">
          <xsl:value-of select="count($next-title/preceding-sibling::*) + 1"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="count($children) + 1"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <!-- Emit all children between title-pos and next-title-pos (exclusive of titles) -->
    <xsl:apply-templates select="$children[
      position() > $title-pos and position() &lt; number($next-title-pos)
    ]"/>
  </xsl:template>

  <!--
    Build reference body following DITA content model:
    (section | simpletable | table | properties | example | ...)*

    Strategy: wrap block content in <section> elements.
    Tables can pass through directly.
  -->
  <xsl:template name="build-ref-body">
    <xsl:param name="body"/>

    <xsl:for-each-group select="$body/*" group-adjacent="
      if (self::table or self::simpletable) then 'table'
      else if (self::example) then 'example'
      else 'content'">
      <xsl:choose>
        <xsl:when test="current-grouping-key() = 'table'">
          <xsl:apply-templates select="current-group()"/>
        </xsl:when>
        <xsl:when test="current-grouping-key() = 'example'">
          <!-- example is a valid direct child of refbody -->
          <xsl:apply-templates select="current-group()"/>
        </xsl:when>
        <xsl:otherwise>
          <section>
            <xsl:apply-templates select="current-group()"/>
          </section>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each-group>
  </xsl:template>

  <!-- Identity transform for most elements -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Clean up: remove db.* outputclass attributes -->
  <xsl:template match="@outputclass[starts-with(., 'db.')]"/>

  <!-- Clean up: remove inline ph elements with db.title outputclass (section title artifacts) -->
  <xsl:template match="ph[@outputclass = 'db.title']"/>

  <!-- Clean up: remove outputclass with underscore prefix -->
  <xsl:template match="@outputclass[starts-with(., '_')]"/>

  <!-- Clean up: remove empty prolog/metadata -->
  <xsl:template match="prolog[not(.//text()[normalize-space()])]"/>
  <xsl:template match="metadata[not(.//text()[normalize-space()])]"/>

  <!-- Clean up: remove XML comment placeholders -->
  <xsl:template match="comment()[contains(., 'not supplied')]"/>

  <!-- Clean up: remove empty body elements -->
  <xsl:template match="body[not(node()[not(self::text()[not(normalize-space())])])]"/>

  <!-- Fix image paths -->
  <xsl:template match="image">
    <image>
      <xsl:for-each select="@*">
        <xsl:choose>
          <xsl:when test="name() = 'href'">
            <xsl:attribute name="href">
              <xsl:choose>
                <xsl:when test="starts-with(., 'images/')">
                  <xsl:value-of select="concat('../', .)"/>
                </xsl:when>
                <xsl:otherwise>
                  <xsl:value-of select="concat('../images/', .)"/>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:attribute>
          </xsl:when>
          <xsl:when test="name() = 'outputclass'"/>
          <!-- Fix invalid frame attribute values -->
          <xsl:when test="name() = 'frame' and not(. = 'top' or . = 'bottom' or . = 'topbot' or . = 'all' or . = 'sides' or . = 'none')"/>
          <xsl:otherwise>
            <xsl:copy/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:apply-templates/>
    </image>
  </xsl:template>

  <!-- Fix invalid frame attributes on tables too -->
  <xsl:template match="@frame[not(. = 'top' or . = 'bottom' or . = 'topbot' or . = 'all' or . = 'sides' or . = 'none')]"/>

  <!-- Remove xml:lang from nested topics -->
  <xsl:template match="topic/topic/@xml:lang | topic/concept/@xml:lang |
                        topic/task/@xml:lang | topic/reference/@xml:lang"/>

</xsl:stylesheet>
