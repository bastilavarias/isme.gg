import tempfile
import unittest
from pathlib import Path

from check_website import check_site


class WebsiteValidationTest(unittest.TestCase):
    def test_checks_lazy_media_and_pages_project_path(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            assets = root / "assets"
            assets.mkdir()
            for name in ("releases.json", "hero.webp", "hero.webm", "font.woff2"):
                (assets / name).touch()
            page = root / "index.html"
            page.write_text(
                '<meta property="og:image" content="https://bastilavarias.github.io/isme.gg/assets/hero.webp">'
                "<style>@font-face{src:url('assets/font.woff2')}</style>"
                '<video poster="assets/hero.webp"><source data-src="assets/hero.webm"></video>'
                '<a id="download" href="#download">Download</a>',
                encoding="utf-8",
            )
            check_site(root)

            (assets / "hero.webm").unlink()
            with self.assertRaisesRegex(ValueError, "Missing local file: assets/hero.webm"):
                check_site(root)

            page.write_text('<img src="/assets/hero.webp">', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Root-relative URL"):
                check_site(root)

    def test_nested_pages_and_registry_assets(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "assets/brands").mkdir(parents=True)
            (root / "data").mkdir()
            (root / "compatibility").mkdir()
            (root / "assets/releases.json").touch()
            (root / "assets/brands/tcl.svg").touch()
            (root / "assets/brands/other.svg").touch()
            (root / "assets/compatibility.js").touch()
            (root / "index.html").write_text(
                '<a id="download" href="compatibility/">Compatibility</a>', encoding="utf-8")
            (root / "compatibility/index.html").write_text(
                '<a href="../#download">Download</a>'
                '<img src="../assets/brands/tcl.svg">'
                '<script src="../assets/compatibility.js"></script>', encoding="utf-8")
            registry = root / "data/compatibility.json"
            registry.write_text('[{"logo":"../assets/brands/other.svg"}]', encoding="utf-8")
            check_site(root)

            (root / "assets/brands/other.svg").unlink()
            with self.assertRaisesRegex(ValueError, "Missing local file: ../assets/brands/other.svg"):
                check_site(root)
            (root / "assets/brands/other.svg").touch()
            registry.unlink()
            with self.assertRaisesRegex(ValueError, "Missing local file: ../data/compatibility.json"):
                check_site(root)
            registry.write_text('[]', encoding="utf-8")
            (root / "assets/compatibility.js").unlink()
            with self.assertRaisesRegex(ValueError, "Missing local file: ../assets/compatibility.js"):
                check_site(root)


if __name__ == "__main__":
    unittest.main()
