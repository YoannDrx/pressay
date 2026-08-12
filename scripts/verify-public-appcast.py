#!/usr/bin/env python3

from __future__ import annotations

import argparse
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def fetch(url: str, attempt: int) -> bytes:
    separator = "&" if "?" in url else "?"
    request = urllib.request.Request(
        f"{url}{separator}verification_attempt={attempt}",
        headers={
            "Cache-Control": "no-cache",
            "User-Agent": "PressayReleaseVerifier/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        if response.status != 200:
            raise RuntimeError(f"appcast HTTP {response.status}")
        return response.read()


def verify(payload: bytes, version: str, build: str) -> None:
    root = ET.fromstring(payload)
    expected_version = root.find(
        f"./channel/item/{{{SPARKLE_NAMESPACE}}}shortVersionString"
    )
    expected_build = root.find(
        f"./channel/item/{{{SPARKLE_NAMESPACE}}}version"
    )
    enclosure = root.find("./channel/item/enclosure")

    if expected_version is None or expected_version.text != version:
        raise RuntimeError(
            f"version publique inattendue: {expected_version.text if expected_version is not None else 'absente'}"
        )
    if expected_build is None or expected_build.text != build:
        raise RuntimeError(
            f"build public inattendu: {expected_build.text if expected_build is not None else 'absent'}"
        )
    if enclosure is None:
        raise RuntimeError("enclosure Sparkle absent")

    signature = enclosure.attrib.get(f"{{{SPARKLE_NAMESPACE}}}edSignature", "")
    expected_url = (
        f"https://github.com/YoannDrx/pressay/releases/download/"
        f"v{version}/Pressay.dmg"
    )
    if enclosure.attrib.get("url") != expected_url:
        raise RuntimeError("URL du DMG non immuable ou inattendue")
    if not signature:
        raise RuntimeError("signature EdDSA absente")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("version")
    parser.add_argument("build")
    parser.add_argument("--attempts", type=int, default=12)
    parser.add_argument("--delay", type=float, default=5)
    args = parser.parse_args()

    last_error: Exception | None = None
    for attempt in range(1, args.attempts + 1):
        try:
            verify(fetch(args.url, attempt), args.version, args.build)
            print(
                f"Appcast public validé: {args.version} ({args.build}), "
                "DMG immuable et signature EdDSA présents"
            )
            return
        except (RuntimeError, urllib.error.URLError, ET.ParseError) as error:
            last_error = error
            if attempt < args.attempts:
                time.sleep(args.delay)

    raise SystemExit(f"Appcast public invalide après {args.attempts} essais: {last_error}")


if __name__ == "__main__":
    main()
