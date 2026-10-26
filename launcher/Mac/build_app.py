#!/usr/bin/env python3
"""Build a self-contained reSwitch.app; optionally sign and install it locally."""
import argparse
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import time
import uuid


APP_ID = "com.odestins.switch.mac"


def bundle_id(path):
    with (path / "Contents/Info.plist").open("rb") as file:
        return plistlib.load(file).get("CFBundleIdentifier")


def copy_executable_file(source, destination):
    """Copy bytes and mode without Finder/iCloud extended attributes."""
    shutil.copyfile(source, destination)
    shutil.copymode(source, destination)
    return destination


def install_bundle(source, destination, previous, verify):
    """Verify before replacement; keep rollback on the destination's filesystem."""
    if destination.name != "reSwitch.app":
        raise ValueError("Install destination must end in reSwitch.app")
    if bundle_id(source) != APP_ID:
        raise ValueError("The built app has an unexpected bundle identifier")
    if destination.is_symlink() or (destination.exists() and bundle_id(destination) != APP_ID):
        raise ValueError("The destination is not an existing reSwitch installation")
    token = uuid.uuid4().hex
    staged = destination.with_name(f".reSwitch.installing-{token}.app")
    backup = destination.with_name(f".reSwitch.previous-{token}.app")
    try:
        shutil.copytree(source, staged, symlinks=True, copy_function=copy_executable_file)
        verify(staged)
        replaced = destination.exists()
        if replaced:
            destination.rename(backup)
        try:
            staged.rename(destination)
        except BaseException:
            if replaced:
                backup.rename(destination)
            raise
        if replaced:
            # Archiving is best-effort after a successful swap. shutil.move also
            # supports a destination on a different drive; rollback never needs it.
            try:
                previous.mkdir(parents=True, exist_ok=True)
                archived = previous / f"reSwitch.previous-{token}.app"
                shutil.move(str(backup), archived)
                backup = archived
            except OSError:
                print("Previous app retained at:", backup)
        os.utime(destination, None)
        return backup if replaced else None
    finally:
        if staged.exists():
            shutil.rmtree(staged)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", default="-")
    parser.add_argument("--install", type=Path, help="Destination such as /Applications/reSwitch.app")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    subprocess.run(["python3", str(root.parent / "Tools/PrepareDiscordMac.py")], check=True)
    subprocess.run(["xcodegen", "generate", "--spec", str(root.parent / "mac-project.yml")], check=True)
    build = Path.home() / "Library/Caches/com.odestins.switch.mac/Build"
    derived = build.parent / "DerivedData"
    subprocess.run(["xcodebuild", "-project", str(root.parent / "reSwitchMac.xcodeproj"), "-scheme", "reSwitchMac",
                    "-configuration", "Release", "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "build"], check=True)
    output = build / "reSwitch.app"
    if output.exists(): shutil.rmtree(output)
    # Preserve versioned framework symlinks, but not iCloud/Finder metadata.
    shutil.copytree(derived / "Build/Products/Release/reSwitch.app", output, symlinks=True, copy_function=shutil.copyfile)
    executable = output / "Contents/MacOS"
    resources = output / "Contents/Resources"
    (executable / "reSwitch").chmod(0o755)
    shutil.copyfile(root.parent / "Resources/Notices.txt", resources / "Notices.txt")
    # Xcode compiles SwitchMac.icon into Assets.car and the compatibility ICNS.
    # A standalone ICNS is wrapped in an extra white frame on current macOS.
    for icon_resource in ("Assets.car", "SwitchMac.icns"):
        if not (resources / icon_resource).is_file():
            raise RuntimeError("Missing compiled Mac icon: " + icon_resource)
    sign = ["codesign", "--force", "--sign", args.identity]
    if args.identity != "-":
        sign += ["--options", "runtime", "--timestamp"]
    framework = output / "Contents/Frameworks/discord_partner_sdk.framework"
    for binary in [framework / "Versions/A/Frameworks/libdiscord_krisp.dylib", framework / "Versions/A/discord_partner_sdk"]:
        binary.chmod(0o755)
    subprocess.run(sign + [str(framework / "Versions/A/Frameworks/libdiscord_krisp.dylib")], check=True)
    subprocess.run(sign + [str(framework)], check=True)
    subprocess.run(sign + ["--entitlements", str(root / "Switch.entitlements"), str(output)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(output)], check=True)
    if args.install:
        destination = args.install.expanduser().absolute()
        if destination.name != "reSwitch.app":
            parser.error("Install destination must end in reSwitch.app")
        previous = build.parent / "Previous"
        install_bundle(output, destination, previous,
                       lambda staged: subprocess.run(["codesign", "--verify", "--deep", "--strict", str(staged)], check=True))
        # Migrate the old visible app name without touching its stable data ID.
        legacy = destination.with_name("Switch.app")
        legacy_info = legacy / "Contents/Info.plist"
        if legacy_info.is_file():
            with legacy_info.open("rb") as file:
                owned = plistlib.load(file).get("CFBundleIdentifier") == "com.odestins.switch.mac"
            if owned:
                previous = build.parent / "Previous"
                previous.mkdir(exist_ok=True)
                shutil.move(str(legacy), previous / ("Switch.before-rebrand-" + str(time.time_ns()) + ".app"))
        # Icon Services also keys its cache by the bundle directory's mtime.
        # copytree preserves that timestamp even when Xcode changed the icon.
        os.utime(destination, None)
        print("Installed:", destination)
    print("Built:", output)


if __name__ == "__main__":
    main()
