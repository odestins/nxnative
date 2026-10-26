#!/usr/bin/env python3
"""Stage only the pinned official iOS SDK from ArcStation's authorized archive."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import zipfile

VERSION = "1.10.19337"
SHA256 = "d784097504685953849cc2842561d8a8013326fe0b8df65a1de63ddefde62045"
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ROOT.parents[1] / "ArcStation" / "Vendor" / "downloads" / f"DiscordSocialSdk-{VERSION}.zip")
    args = parser.parse_args()
    with args.archive.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    if digest != SHA256:
        raise SystemExit("Discord SDK archive does not match the reviewed ArcStation dependency.")
    vendor = ROOT / "Vendor"
    vendor.mkdir(exist_ok=True)
    destination = vendor / "discord_social_sdk"
    if destination.exists():
        raise SystemExit("SDK is already staged. Preserve it or remove this generated directory before restaging.")
    prefixes = ("lib/release/discord_partner_sdk.xcframework/", "lib/release/discord_partner_sdk_krisp.xcframework/")
    with tempfile.TemporaryDirectory(dir=vendor) as temporary:
        stage = Path(temporary) / "discord_social_sdk"
        stage.mkdir()
        hashes = {}
        with zipfile.ZipFile(args.archive) as archive:
            for entry in archive.infolist():
                name = entry.filename.removeprefix("discord_social_sdk/")
                if name != "License-Notices.txt" and not name.startswith(prefixes):
                    continue
                path = Path(name)
                if path.is_absolute() or ".." in path.parts or entry.file_size > 256 * 1024 * 1024:
                    raise SystemExit("Invalid SDK archive entry.")
                if entry.is_dir(): continue
                data = archive.read(entry)
                target = stage / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                target.chmod((entry.external_attr >> 16) & 0o777 or 0o644)
                hashes[name] = hashlib.sha256(data).hexdigest()
        for prefix in prefixes:
            if not (stage / prefix / "Info.plist").is_file():
                raise SystemExit("The SDK archive is missing an iOS framework.")
        (stage / "verified.json").write_text(json.dumps({"version": VERSION, "archiveSHA256": digest, "files": hashes}, indent=2) + "\n")
        shutil.move(stage, destination)
    print(f"Staged official Discord Social SDK {VERSION}: {len(hashes)} verified iOS files.")

if __name__ == "__main__": main()
