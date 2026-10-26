#!/usr/bin/env python3
"""Prepare an already extracted native game for the Switch Mac launcher.

Game assets stay in their existing build folder. This does not extract NSPs or
make unsupported titles playable. No keys or source binaries enter the repo.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def atomic_json(path, value):
    temporary = path.with_suffix(path.suffix + ".new")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--card", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--version", required=True, help="Extracted version directory, e.g. v65536")
    parser.add_argument("--note", default="")
    parser.add_argument("--blocked", action="store_true", help="Keep a card visible without allowing play")
    parser.add_argument("--skip-build", action="store_true", help="Reuse this game's already prepared MacPlayer runtime")
    parser.add_argument("--identity", default="-", help="codesign identity; default is local ad-hoc signing")
    parser.add_argument("--install-library", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    card = json.loads(args.card.read_text())
    if "games" in card:
        if len(card["games"]) != 1:
            parser.error("Use a card containing exactly one game")
        card = card["games"][0]
    tid = card["titleID"]
    if not re.fullmatch(r"[0-9A-F]{16}", tid) or not re.fullmatch(r"v[0-9]+", args.version):
        parser.error("Invalid title ID or extracted version")
    root = args.build.resolve(strict=True)
    if root.name != tid + "_build":
        parser.error("The build folder must match the card's title ID")
    chain = re.search(r'DMSH_CHAIN "([a-f0-9]+)"', (repo / "dm/gfx/nvn/dmsh_chain.h").read_text())[1]
    descriptor = dict(schemaVersion=1, manifest=card, root=str(root), modules="patched_" + args.version,
                      romfs="extract/" + args.version + "/RomFS", shaderMap="profile/" + tid + "/shader_map.tsv",
                      shaderChain=chain, playable=not args.blocked, notes=args.note)
    if not args.blocked:
        required = [descriptor["modules"] + "/main.patched.bin", descriptor["romfs"], descriptor["shaderMap"],
                    "shader/cache/b-" + chain + "/inputs.tsv"]
        for relative in required:
            if not (root / relative).exists():
                parser.error("Missing prepared resource: " + relative)
        target = root / "MacPlayer/Runtime"
        target.mkdir(parents=True, exist_ok=True)
        if not args.skip_build:
            # No concurrent host builds: the upstream make target is shared.
            with (target / "build.log").open("w") as log:
                subprocess.run(["make", "-C", str(repo / "dm/host"), "GAME=" + tid, "-j8"],
                               stdout=log, stderr=subprocess.STDOUT, check=True)
            candidate = target / "dmhost.new"
            shutil.copy2(repo / "dm/host/dmhost", candidate)
            command = ["codesign", "--force", "--sign", args.identity]
            if args.identity != "-":
                command.append("--timestamp")
            subprocess.run(command + [str(candidate)], check=True)
            os.replace(candidate, target / "dmhost")
        if not os.access(target / "dmhost", os.X_OK):
            parser.error("The game's native Mac runtime has not been prepared")
        # Reuse the existing generated shared-font stand-ins, including button
        # glyphs. The Mac fallback font does not contain the controller icons.
        fonts = root / "font"
        fonts.mkdir(exist_ok=True)
        for name in ("standard.ttf", "nintendo_ext.ttf"):
            source = root / "xcode/Gen/dm/font" / name
            if source.exists() and not (fonts / name).exists():
                shutil.copyfile(source, fonts / name)
    atomic_json(root / "SwitchMac.switchmac", descriptor)
    if args.install_library:
        library = Path.home() / "Library/Application Support/com.odestins.switch.mac/library.json"
        library.parent.mkdir(parents=True, exist_ok=True)
        document = json.loads(library.read_text()) if library.exists() else dict(schemaVersion=1, games=[])
        if document.get("schemaVersion") != 1 or not isinstance(document.get("games"), list):
            parser.error("Existing library is invalid; refusing to overwrite it")
        games = document["games"]
        for index, entry in enumerate(games):
            if entry["manifest"]["titleID"] == tid:
                games[index] = descriptor
                break
        else:
            games.append(descriptor)
        if library.exists():
            shutil.copy2(library, library.with_suffix(".json.backup"))
        atomic_json(library, document)
    print("Prepared Mac card:", card["name"], "(unavailable)" if args.blocked else "")


if __name__ == "__main__":
    main()
