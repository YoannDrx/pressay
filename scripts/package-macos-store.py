#!/usr/bin/env python3
"""Package an already signed Tauri Store app with its matching crash symbols."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("dsym", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--installer-identity", required=True)
    args = parser.parse_args()
    app, dsym, output = args.app.resolve(), args.dsym.resolve(), args.output.resolve()
    if output.exists():
        parser.error("output must be a new directory; existing artifacts are preserved")

    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info["CFBundleIdentifier"] != "fr.yodev.pressay":
        parser.error("expected the Pressay Mac App Store bundle")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    signature_details = subprocess.run(
        ["codesign", "-dvv", str(app)], check=True, capture_output=True, text=True
    ).stderr
    signing_identity = next(
        (line.removeprefix("Authority=") for line in signature_details.splitlines()
         if line.startswith("Authority=")),
        None,
    )
    if not signing_identity:
        parser.error("a distribution signing identity is required")
    entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(app)))
    profile = plistlib.loads(
        run("security", "cms", "-D", "-i", str(app / "Contents/embedded.provisionprofile"))
    )
    for key in ["com.apple.application-identifier", "com.apple.developer.team-identifier"]:
        if entitlements[key] != profile["Entitlements"][key]:
            parser.error(f"profile mismatch: {key}")
    apple_sign_in = entitlements.get("com.apple.developer.applesignin")
    if apple_sign_in != ["Default"] or apple_sign_in != profile["Entitlements"].get(
        "com.apple.developer.applesignin"
    ):
        parser.error("Sign in with Apple entitlement does not match the profile")
    with tempfile.TemporaryDirectory(prefix="pressay-signature-") as directory:
        prefix = str(Path(directory) / "certificate-")
        run("codesign", "-d", f"--extract-certificates={prefix}", str(app))
        if Path(prefix + "0").read_bytes() not in profile["DeveloperCertificates"]:
            parser.error("signing certificate is not allowed by the provisioning profile")
    if not entitlements.get("com.apple.security.app-sandbox"):
        parser.error("App Sandbox must be enabled")
    if entitlements.get("get-task-allow") or entitlements.get(
        "com.apple.security.get-task-allow"
    ):
        parser.error("debugging entitlements must not ship")
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    if profile["ExpirationDate"] <= now:
        parser.error("provisioning profile has expired")

    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    symbols_check = Path(__file__).with_name("check-macos-symbols.sh")
    print(run("bash", str(symbols_check), str(executable), str(dsym)).decode().strip())

    # Keep an Organizer archive as well as the installer, so Xcode can validate
    # and upload the app and dSYM using the developer's existing signed-in account.
    archive = output / "Pressay.xcarchive"
    (archive / "Products/Applications").mkdir(parents=True)
    (archive / "dSYMs").mkdir()
    run("ditto", str(app), str(archive / "Products/Applications/Pressay.app"))
    run("ditto", str(dsym), str(archive / "dSYMs" / dsym.name))
    archive_info = {
        "ArchiveVersion": 2,
        "CreationDate": now,
        "Name": "Pressay",
        "SchemeName": "Pressay",
        "ApplicationProperties": {
            "ApplicationPath": "Applications/Pressay.app",
            "CFBundleIdentifier": info["CFBundleIdentifier"],
            "CFBundleShortVersionString": info["CFBundleShortVersionString"],
            "CFBundleVersion": info["CFBundleVersion"],
            "SigningIdentity": signing_identity,
            "Team": entitlements["com.apple.developer.team-identifier"],
            "Architectures": run("lipo", "-archs", str(executable)).decode().split(),
        },
    }
    (archive / "Info.plist").write_bytes(plistlib.dumps(archive_info))
    package = output / f"Pressay-{info['CFBundleShortVersionString']}-{info['CFBundleVersion']}.pkg"
    run(
        "xcrun", "productbuild", "--sign", args.installer_identity,
        "--component", str(app), "/Applications", str(package),
    )
    signature = run("pkgutil", "--check-signature", str(package)).decode()
    (output / "package-signature.txt").write_text(signature)
    checksum = hashlib.sha256(package.read_bytes()).hexdigest()
    (output / "SHA256SUMS").write_text(f"{checksum}  {package.name}\n")
    evidence = {
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "bundleId": info["CFBundleIdentifier"],
        "localPackageSha256": checksum,
        "symbolsMatch": True,
        "uploaded": False,
    }
    (output / "package-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"Prepared {archive} and {package}. Nothing uploaded.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        detail = error.stderr or str(error)
        if isinstance(detail, bytes):
            detail = detail.decode(errors="replace")
        print(detail, file=sys.stderr)
        sys.exit(error.returncode)
