import unittest
from check_whats_new import validate, main


class WhatsNewReleaseTests(unittest.TestCase):
    def test_current_version_registered(self):
        main()

    def test_missing_or_reused_builder_rejected(self):
        with self.assertRaises(ValueError):
            validate("0.3.0+18", "  '0.2.0+17':buildV020,")
        with self.assertRaises(ValueError):
            validate("0.3.0+18", "  '0.2.0+17':buildV020,\n  '0.3.0+18':buildV020,")
        validate("0.3.0+18", "  '0.2.0+17':buildV020,\n  '0.3.0+18':buildV030,")
