#!/usr/bin/env python3

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def latest_build(path: Path) -> int:
    if not path.exists() or path.stat().st_size == 0:
        return 0
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return 0
    builds: list[int] = []
    for item in root.findall("./channel/item"):
        enclosure = item.find("enclosure")
        value = (
            enclosure.attrib.get(f"{{{SPARKLE}}}version")
            if enclosure is not None
            else None
        )
        if not value:
            version_node = item.find(f"{{{SPARKLE}}}version")
            value = version_node.text if version_node is not None else None
        try:
            builds.append(int(value or ""))
        except ValueError:
            continue
    return max(builds, default=0)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: latest-appcast-build.py APPCAST")
    print(latest_build(Path(sys.argv[1])))
