"""Regression coverage for the refused 2.0.4 export-compliance archive."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "package_macos_store", Path(__file__).with_name("package-macos-store.py")
)
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class ExportComplianceTests(unittest.TestCase):
    def test_rejects_missing_or_mismatched_apple_code(self):
        for info in [
            {},
            {"ITSAppUsesNonExemptEncryption": True},
            {"ITSAppUsesNonExemptEncryption": True, "ITSEncryptionExportComplianceCode": "other"},
            {"ITSAppUsesNonExemptEncryption": False, "ITSEncryptionExportComplianceCode": "synthetic"},
            {"ITSAppUsesNonExemptEncryption": "true", "ITSEncryptionExportComplianceCode": "synthetic"},
        ]:
            with self.subTest(info=info), self.assertRaises(ValueError):
                packager.validate_export_compliance(info, "synthetic")

    def test_rejects_empty_configuration_even_if_bundle_matches(self):
        for code in ["", "   "]:
            with self.subTest(code=code), self.assertRaises(ValueError):
                packager.validate_export_compliance({
                    "ITSAppUsesNonExemptEncryption": True,
                    "ITSEncryptionExportComplianceCode": code,
                }, code)

    def test_accepts_the_exact_approved_code(self):
        packager.validate_export_compliance({
            "ITSAppUsesNonExemptEncryption": True,
            "ITSEncryptionExportComplianceCode": "synthetic",
        }, "synthetic")


if __name__ == "__main__":
    unittest.main()
