#!/usr/bin/env python3

import argparse
import copy
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def version(item: ET.Element) -> int:
    enclosure = item.find("enclosure")
    if enclosure is None:
        return -1
    value = enclosure.attrib.get(f"{{{SPARKLE}}}version", "-1")
    try:
        return int(value)
    except ValueError:
        return -1


def channel(item: ET.Element) -> str:
    node = item.find(f"{{{SPARKLE}}}channel")
    return node.text.strip() if node is not None and node.text else "stable"


def load_items(path: Path) -> list[ET.Element]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    root = ET.parse(path).getroot()
    return [copy.deepcopy(item) for item in root.findall("./channel/item")]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current", type=Path)
    parser.add_argument("--new", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--channel", choices=("stable", "beta"), required=True)
    args = parser.parse_args()

    new_tree = ET.parse(args.new)
    new_root = new_tree.getroot()
    new_items = new_root.findall("./channel/item")
    if len(new_items) != 1:
        raise SystemExit("Le nouvel appcast doit contenir exactement un item.")

    new_item = copy.deepcopy(new_items[0])
    existing_channel = new_item.find(f"{{{SPARKLE}}}channel")
    if existing_channel is not None:
        new_item.remove(existing_channel)
    if args.channel == "beta":
        node = ET.Element(f"{{{SPARKLE}}}channel")
        node.text = "beta"
        new_item.insert(0, node)

    by_version = {
        version(item): item
        for item in load_items(args.current)
        if version(item) >= 0
    }
    by_version[version(new_item)] = new_item

    stable = sorted(
        (item for item in by_version.values() if channel(item) == "stable"),
        key=version,
        reverse=True,
    )[:3]
    beta = sorted(
        (item for item in by_version.values() if channel(item) == "beta"),
        key=version,
        reverse=True,
    )[:5]
    retained = sorted(stable + beta, key=version, reverse=True)

    output_root = copy.deepcopy(new_root)
    output_channel = output_root.find("./channel")
    if output_channel is None:
        raise SystemExit("Canal RSS absent du nouvel appcast.")
    for item in output_channel.findall("item"):
        output_channel.remove(item)
    for item in retained:
        output_channel.append(item)

    ET.ElementTree(output_root).write(
        args.output,
        encoding="utf-8",
        xml_declaration=True,
    )


if __name__ == "__main__":
    main()
