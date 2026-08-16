# /// script
# requires-python = ">=3.10"
# dependencies = ["boto3", "cryptography", "tqdm"]
# ///
"""Publish license-audited model artifacts to Pressay's S3-compatible store.

The script never downloads from a third-party model registry. Release operators
must first place the exact, reviewed files in a local source directory. Every
source file is checked against the signed catalog's byte size and SHA-256 before
upload. Object keys are immutable:

    {model_id}/{revision}/{filename}

Default mode is a read-only plan. `--execute --source-dir DIR` uploads missing
objects. `--verify` streams every object back and verifies its digest.

Environment:
  R2_ENDPOINT
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  R2_BUCKET

Examples:
  uv run scripts/mirror_models.py
  uv run scripts/mirror_models.py --execute --source-dir /secure/audited-models
  uv run scripts/mirror_models.py --verify
"""

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import boto3
from boto3.s3.transfer import TransferConfig
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from tqdm import tqdm

CACHE_CONTROL = "public, max-age=31536000, immutable"
CHUNK = 8 * 1024 * 1024
TRANSFER = TransferConfig(max_concurrency=8, multipart_chunksize=32 * 1024 * 1024)


def say(message: str) -> None:
    tqdm.write(message)


def make_s3():
    values = [
        os.environ.get("R2_ENDPOINT"),
        os.environ.get("R2_ACCESS_KEY_ID"),
        os.environ.get("R2_SECRET_ACCESS_KEY"),
        os.environ.get("R2_BUCKET"),
    ]
    if not all(values):
        return None, None
    endpoint, key, secret, bucket = values
    client = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=key,
        aws_secret_access_key=secret,
    )
    return client, bucket


def head_metadata(s3, bucket: str, key: str):
    try:
        return s3.head_object(Bucket=bucket, Key=key).get("Metadata", {})
    except s3.exceptions.ClientError as error:
        if error.response["Error"]["Code"] in {"404", "NoSuchKey", "NotFound"}:
            return None
        raise


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def checked_source(source_dir: Path, file_spec: dict) -> Path:
    path = source_dir / file_spec["filename"]
    if not path.is_file():
        raise RuntimeError(f"missing audited source file: {path}")
    actual_size = path.stat().st_size
    if actual_size != file_spec["size_bytes"]:
        raise RuntimeError(
            f"size mismatch for {path.name}: {actual_size} != {file_spec['size_bytes']}"
        )
    actual_hash = sha256_file(path)
    if actual_hash != file_spec["sha256"]:
        raise RuntimeError(
            f"SHA-256 mismatch for {path.name}: {actual_hash} != {file_spec['sha256']}"
        )
    return path


def verify_bucket(s3, bucket: str, jobs: list[tuple[str, dict]]) -> int:
    failures = 0
    for key, file_spec in jobs:
        try:
            body = s3.get_object(Bucket=bucket, Key=key)["Body"]
        except s3.exceptions.ClientError as error:
            if error.response["Error"]["Code"] in {"404", "NoSuchKey", "NotFound"}:
                say(f"MISSING  {key}")
                failures += 1
                continue
            raise

        digest = hashlib.sha256()
        started = time.monotonic()
        for chunk in iter(lambda: body.read(CHUNK), b""):
            digest.update(chunk)
        elapsed = max(time.monotonic() - started, 1e-9)
        rate = file_spec["size_bytes"] / elapsed / 1e6
        if digest.hexdigest() == file_spec["sha256"]:
            say(f"ok       {key}  ({rate:.0f} MB/s)")
        else:
            say(f"BAD      {key}  object does not match the signed catalog")
            failures += 1
    return failures


def load_jobs(catalog_path: Path, only: str | None) -> list[tuple[str, dict]]:
    catalog_bytes = catalog_path.read_bytes()
    public_key = Ed25519PublicKey.from_public_bytes(
        catalog_path.with_name("catalog.pub").read_bytes()
    )
    public_key.verify(
        catalog_path.with_name("catalog.sig").read_bytes(), catalog_bytes
    )
    catalog = json.loads(catalog_bytes)
    jobs: list[tuple[str, dict]] = []
    for model in catalog["models"]:
        if only and only not in model["id"]:
            continue
        default_quant = model["default_quant"]
        matching = [file for file in model["files"] if file["quant"] == default_quant]
        if len(matching) != 1:
            raise RuntimeError(
                f"{model['id']} must have exactly one file for {default_quant}"
            )
        file_spec = matching[0]
        key = f"{model['id']}/{model['revision']}/{file_spec['filename']}"
        jobs.append((key, file_spec))
    return jobs


def main() -> None:
    default_catalog = (
        Path(__file__).resolve().parent.parent
        / "src-tauri"
        / "src"
        / "catalog"
        / "catalog.json"
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalog", nargs="?", type=Path, default=default_catalog)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--only")
    args = parser.parse_args()

    if args.execute and args.verify:
        parser.error("--execute and --verify are mutually exclusive")
    if args.execute and args.source_dir is None:
        parser.error("--execute requires --source-dir")

    jobs = load_jobs(args.catalog, args.only)
    s3, bucket = make_s3()

    if args.verify:
        if s3 is None:
            sys.exit("--verify requires all R2 environment variables")
        failures = verify_bucket(s3, bucket, jobs)
        print(f"verified {len(jobs)} object(s), {failures} problem(s)")
        raise SystemExit(1 if failures else 0)

    if args.execute and s3 is None:
        sys.exit("--execute requires all R2 environment variables")

    tally = {"skip": 0, "upload": 0, "mismatch": 0}
    for key, file_spec in jobs:
        metadata = head_metadata(s3, bucket, key) if s3 is not None else None
        if metadata is not None:
            if metadata.get("sha256") == file_spec["sha256"]:
                say(f"skip     {key}")
                tally["skip"] += 1
            else:
                say(f"MISMATCH {key}  immutable object has unexpected metadata")
                tally["mismatch"] += 1
            continue

        if not args.execute:
            say(f"DRY upload {key}  ({file_spec['size_bytes'] / 1e9:.2f} GB)")
            tally["upload"] += 1
            continue

        source = checked_source(args.source_dir, file_spec)
        s3.upload_file(
            str(source),
            bucket,
            key,
            ExtraArgs={
                "Metadata": {"sha256": file_spec["sha256"]},
                "CacheControl": CACHE_CONTROL,
                "ContentType": "application/octet-stream",
            },
            Config=TRANSFER,
        )
        say(f"uploaded {key}")
        tally["upload"] += 1

    print(
        f"{'DRY RUN — ' if not args.execute else ''}"
        f"skip {tally['skip']}, upload {tally['upload']}, "
        f"mismatch {tally['mismatch']}"
    )
    if tally["mismatch"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
