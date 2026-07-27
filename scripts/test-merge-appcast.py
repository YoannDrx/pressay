#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

SCRIPT = Path(__file__).with_name("merge-appcast.py")
SPEC = importlib.util.spec_from_file_location("merge_appcast", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def appcast(items: list[tuple[int, str]]) -> str:
    rows = []
    for build, channel in items:
        channel_xml = (
            "<sparkle:channel>beta</sparkle:channel>"
            if channel == "beta"
            else ""
        )
        rows.append(
            f"""
            <item>
              {channel_xml}
              <title>Build {build}</title>
              <enclosure
                url="https://example.com/{build}.dmg"
                sparkle:version="{build}"
                sparkle:edSignature="signature-{build}" />
            </item>
            """
        )
    return f"""<?xml version="1.0"?>
    <rss xmlns:sparkle="{SPARKLE}" version="2.0">
      <channel><title>Pressay</title>{''.join(rows)}</channel>
    </rss>
    """


class MergeAppcastTests(unittest.TestCase):
    def test_retains_three_stable_and_five_beta_sorted_by_build(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            current = root / "current.xml"
            new = root / "new.xml"
            current.write_text(
                appcast(
                    [
                        (12000, "stable"),
                        (11900, "stable"),
                        (11800, "stable"),
                        (11700, "stable"),
                        (12001, "beta"),
                        (12002, "beta"),
                        (12003, "beta"),
                        (12004, "beta"),
                        (12005, "beta"),
                        (12006, "beta"),
                    ]
                )
            )
            new.write_text(appcast([(12099, "stable")]))

            previous_argv = list(__import__("sys").argv)
            __import__("sys").argv = [
                str(SCRIPT),
                "--current",
                str(current),
                "--new",
                str(new),
                "--output",
                str(root / "output.xml"),
                "--channel",
                "stable",
            ]
            try:
                MODULE.main()
            finally:
                __import__("sys").argv = previous_argv

            tree = ET.parse(root / "output.xml")
            items = tree.getroot().findall("./channel/item")
            builds = [MODULE.version(item) for item in items]
            self.assertEqual(
                builds,
                [12099, 12006, 12005, 12004, 12003, 12002, 12000, 11900],
            )
            stable = [
                item for item in items if MODULE.channel(item) == "stable"
            ]
            beta = [
                item for item in items if MODULE.channel(item) == "beta"
            ]
            self.assertEqual(len(stable), 3)
            self.assertEqual(len(beta), 5)

    def test_beta_item_receives_channel(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            current = root / "current.xml"
            new = root / "new.xml"
            current.write_text(appcast([]))
            new.write_text(appcast([(12001, "stable")]))

            previous_argv = list(__import__("sys").argv)
            __import__("sys").argv = [
                str(SCRIPT),
                "--current",
                str(current),
                "--new",
                str(new),
                "--output",
                str(root / "output.xml"),
                "--channel",
                "beta",
            ]
            try:
                MODULE.main()
            finally:
                __import__("sys").argv = previous_argv

            item = ET.parse(root / "output.xml").getroot().find(
                "./channel/item"
            )
            assert item is not None
            self.assertEqual(MODULE.channel(item), "beta")


if __name__ == "__main__":
    unittest.main()
