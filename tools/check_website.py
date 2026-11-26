"""Check local HTML references in the curated GitHub Pages artifact."""

import argparse
import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


PAGE_HOST = "bastilavarias.github.io"
PAGE_PREFIX = "/isme.gg/"
IMAGE_META = {"og:image", "twitter:image"}


class PageReferences(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.urls = set()

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if attrs.get("id"):
            self.ids.add(attrs["id"])
        for name in ("href", "src", "poster", "data-src"):
            if attrs.get(name):
                self.urls.add(attrs[name])
        if tag == "meta" and IMAGE_META.intersection((attrs.get("name"), attrs.get("property"))):
            self.urls.add(attrs["content"])


def check_site(root):
    root = root.resolve()
    html = (root / "index.html").read_text(encoding="utf-8")
    page = PageReferences()
    page.feed(html)
    page.urls.update(re.findall(r"""url\(\s*['"]?([^'")\s]+)""", html))
    page.urls.add("assets/releases.json")
    errors = []
    for reference in sorted(page.urls):
        url = urlsplit(reference)
        path = unquote(url.path)
        if url.netloc == PAGE_HOST:
            if url.scheme != "https" or not path.startswith(PAGE_PREFIX):
                errors.append(f"Invalid production URL: {reference}")
                continue
            path = path[len(PAGE_PREFIX):]
        elif url.scheme or url.netloc:
            continue
        elif path.startswith("/"):
            errors.append(f"Root-relative URL breaks the Pages project path: {reference}")
            continue
        target = (root / (path or "index.html")).resolve()
        if not target.is_relative_to(root) or not target.is_file():
            errors.append(f"Missing local file: {reference}")
        if target == root / "index.html" and url.fragment and unquote(url.fragment) not in page.ids:
            errors.append(f"Missing page section: {reference}")
    if errors:
        raise ValueError("\n".join(errors))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    try:
        check_site(parser.parse_args().root)
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
    print("GitHub Pages asset references verified.")
