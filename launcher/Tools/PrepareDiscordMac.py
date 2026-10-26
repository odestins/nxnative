#!/usr/bin/env python3
"""Stage the pinned official Mac SDK from the owner's ArcStation archive."""
import argparse
import hashlib
from pathlib import Path
import shutil
import tempfile
import zipfile
from PrepareDiscord import VERSION, SHA256, ROOT

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ROOT.parents[1] / "ArcStation/Vendor/downloads" / f"DiscordSocialSdk-{VERSION}.zip")
    args = parser.parse_args()
    destination = ROOT / "Vendor/discord_mac"
    if (destination / "discord_partner_sdk.framework/discord_partner_sdk").exists():
        print("Mac Discord SDK is already staged."); return
    with args.archive.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != SHA256:
            raise SystemExit("Discord SDK archive does not match the pinned dependency.")
    destination.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        stage = Path(temp)
        with zipfile.ZipFile(args.archive) as archive:
            prefix = "discord_social_sdk/lib/release/discord_partner_sdk.framework/"
            for entry in archive.infolist():
                if not entry.filename.startswith(prefix) or entry.is_dir(): continue
                relative = Path(entry.filename.removeprefix(prefix))
                if relative.is_absolute() or ".." in relative.parts: raise SystemExit("Invalid SDK path")
                target = stage / "discord_partner_sdk.framework" / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                # zip preserves the framework's standard relative symlinks.
                if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    link = archive.read(entry).decode()
                    if Path(link).is_absolute() or ".." in Path(link).parts: raise SystemExit("Invalid SDK symlink")
                    target.symlink_to(link)
                else:
                    target.write_bytes(archive.read(entry)); target.chmod((entry.external_attr >> 16) & 0o777 or 0o644)
        if not (stage / "discord_partner_sdk.framework/discord_partner_sdk").exists(): raise SystemExit("Mac framework is missing")
        shutil.copytree(stage, destination, symlinks=True)
    print("Staged pinned Mac Discord SDK " + VERSION)

if __name__ == "__main__": main()
