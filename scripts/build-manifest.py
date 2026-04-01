#!/usr/bin/env python3
"""Scan AsciiDoc files and build a content-type manifest XML.

For each .adoc file, extracts:
  1. :_mod-docs-content-type: attribute (primary)
  2. Filename prefix fallback (con_, proc_, ref_, assembly_)
  3. Section ID from [id="..."] or derived from filename

Outputs XML manifest to stdout.
"""

import os
import re
import sys
import xml.etree.ElementTree as ET
from xml.dom import minidom

CONTENT_TYPE_MAP = {
    "CONCEPT": "concept",
    "PROCEDURE": "task",
    "REFERENCE": "reference",
    "ASSEMBLY": "assembly",
}

PREFIX_MAP = {
    "con_": "concept",
    "proc_": "task",
    "ref_": "reference",
    "assembly_": "assembly",
}


def extract_content_type(filepath):
    """Extract content type from .adoc file."""
    basename = os.path.basename(filepath)
    content_type = None
    section_id = None

    try:
        with open(filepath, "r", errors="replace") as f:
            for line in f:
                # Check for :_mod-docs-content-type:
                m = re.match(r'^:_mod-docs-content-type:\s*(\w+)', line)
                if m:
                    raw_type = m.group(1).upper()
                    content_type = CONTENT_TYPE_MAP.get(raw_type)

                # Check for [id="..."]
                m = re.match(r'^\[id=["\']([^"\']+)["\']', line)
                if m:
                    section_id = m.group(1)
                    # Strip context suffix like _{context}
                    section_id = re.sub(r'_\{[^}]+\}$', '', section_id)
    except Exception:
        pass

    # Fallback: derive from filename prefix
    if not content_type:
        for prefix, ctype in PREFIX_MAP.items():
            if basename.startswith(prefix):
                content_type = ctype
                break

    # Fallback: derive ID from filename
    if not section_id:
        section_id = os.path.splitext(basename)[0]

    return section_id, content_type, basename


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else "src"

    root = ET.Element("manifest")

    for dirpath, _, filenames in os.walk(src_dir):
        for fname in sorted(filenames):
            if not fname.endswith(".adoc"):
                continue
            if fname.startswith("_"):
                continue

            filepath = os.path.join(dirpath, fname)
            section_id, content_type, source = extract_content_type(filepath)

            if content_type:
                entry = ET.SubElement(root, "entry")
                entry.set("id", section_id)
                entry.set("type", content_type)
                entry.set("source", source)

    xml_str = minidom.parseString(ET.tostring(root, encoding="unicode")).toprettyxml(indent="  ")
    # Remove extra XML declaration from minidom
    lines = xml_str.split("\n")
    if lines[0].startswith("<?xml"):
        lines = lines[1:]
    print('<?xml version="1.0" encoding="UTF-8"?>')
    print("\n".join(lines))


if __name__ == "__main__":
    main()
