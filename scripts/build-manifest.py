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


def extract_content_types(filepath):
    """Extract content type and all section IDs from .adoc file.

    Returns a list of (section_id, content_type, source) tuples.
    The file-level content type is inherited by all subsection IDs.
    """
    basename = os.path.basename(filepath)
    content_type = None
    section_ids = []

    try:
        with open(filepath, "r", errors="replace") as f:
            for line in f:
                if not content_type:
                    m = re.match(r'^:_mod-docs-content-type:\s*(\w+)', line)
                    if m:
                        raw_type = m.group(1).upper()
                        content_type = CONTENT_TYPE_MAP.get(raw_type)

                m = re.match(r'^\[id=["\']([^"\']+)["\']', line)
                if m:
                    sid = m.group(1)
                    sid = re.sub(r'_\{[^}]+\}$', '', sid)
                    section_ids.append(sid)
    except Exception:
        pass

    # Fallback: derive from filename prefix
    if not content_type:
        for prefix, ctype in PREFIX_MAP.items():
            if basename.startswith(prefix):
                content_type = ctype
                break

    # Fallback: derive ID from filename
    if not section_ids:
        section_ids.append(os.path.splitext(basename)[0])

    return [(sid, content_type, basename) for sid in section_ids]


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else "src"

    root = ET.Element("manifest")
    seen_ids = set()

    for dirpath, dirnames, filenames in os.walk(src_dir):
        dirnames[:] = [d for d in dirnames if not d.startswith(('.', '_'))]

        for fname in sorted(filenames):
            if not fname.endswith(".adoc"):
                continue
            if fname.startswith("_"):
                continue

            filepath = os.path.join(dirpath, fname)
            for section_id, content_type, source in extract_content_types(filepath):
                if content_type and section_id not in seen_ids:
                    seen_ids.add(section_id)
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
