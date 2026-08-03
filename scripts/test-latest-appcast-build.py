#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("latest-appcast-build.py")
SPEC = importlib.util.spec_from_file_location("latest_appcast_build", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class LatestAppcastBuildTests(unittest.TestCase):
    def test_reads_version_attribute_and_element(self) -> None:
        xml = f"""<?xml version="1.0"?>
        <rss xmlns:sparkle="{SPARKLE}" version="2.0">
          <channel>
            <item>
              <enclosure sparkle:version="12101" />
            </item>
            <item>
              <sparkle:version>12102</sparkle:version>
              <enclosure />
            </item>
          </channel>
        </rss>
        """
        with tempfile.TemporaryDirectory() as folder:
            appcast = Path(folder) / "appcast.xml"
            appcast.write_text(xml)
            self.assertEqual(MODULE.latest_build(appcast), 12102)

    def test_returns_zero_for_missing_or_invalid_appcast(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertEqual(MODULE.latest_build(root / "missing.xml"), 0)
            invalid = root / "invalid.xml"
            invalid.write_text("not xml")
            self.assertEqual(MODULE.latest_build(invalid), 0)


if __name__ == "__main__":
    unittest.main()
