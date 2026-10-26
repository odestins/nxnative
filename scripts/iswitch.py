#!/usr/bin/env python3
"""Player-facing reSwitch preparation assistant; game data stays beside the chosen NSPs."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'dm/ios/tools'))
import iswitch_assets


def tool_environment():
    env = dict(os.environ)
    env['PATH'] = os.pathsep.join(['/opt/homebrew/bin', '/usr/local/bin', '/usr/local/share/dotnet', env.get('PATH', '/usr/bin:/bin')])
    dotnet = shutil.which('dotnet', path=env['PATH'])
    if dotnet:
        binary_parent = Path(dotnet).resolve().parent
        # Homebrew's launcher lives in bin/, while apphosts require libexec/.
        candidates = [binary_parent, binary_parent.parent / 'libexec', Path('/usr/local/share/dotnet')]
        for candidate in candidates:
            if (candidate / 'host' / 'fxr').is_dir():
                env.setdefault('DOTNET_ROOT', str(candidate))
                break
    env.setdefault('DOTNET_CLI_TELEMETRY_OPTOUT', '1')
    return env


def doctor():
    env = tool_environment()
    failures = []
    if platform.system() != 'Darwin':
        failures.append('A Mac with Xcode is required to prepare iPhone game apps.')
    tools = {'xcodebuild': 'Install and open Xcode.', 'xcodegen': 'brew install xcodegen',
             'dotnet': 'brew install dotnet@10', 'zstd': 'brew install zstd',
             'spirv-cross': 'brew install spirv-cross', 'glslangValidator': 'brew install glslang'}
    for name, instruction in tools.items():
        found = shutil.which(name, path=env['PATH'])
        print(f'{"OK     " if found else "MISSING"}  {name}')
        if not found:
            failures.append(instruction)
    for name, package in [('lz4.block', 'lz4'), ('capstone', 'capstone'), ('fontTools', 'fonttools')]:
        try:
            available = importlib.util.find_spec(name) is not None
        except ModuleNotFoundError:
            available = False
        print(f'{"OK     " if available else "MISSING"}  Python {package}')
        if not available:
            failures.append(f'Install {package} in a Python virtual environment beside your game files (see docs/iswitch.md).')
    if sys.version_info < (3, 14):
        try:
            zstd = importlib.util.find_spec('backports.zstd') is not None
        except ModuleNotFoundError:
            zstd = False
        if not zstd:
            failures.append('Install backports.zstd in that Python environment.')
    if shutil.which('xcodebuild', path=env['PATH']):
        for sdk in ('iphoneos', 'macosx'):
            result = subprocess.run(['xcrun', '-sdk', sdk, 'metal', '--version'], env=env, capture_output=True, text=True)
            print(f'{"OK     " if result.returncode == 0 else "MISSING"}  {sdk} Metal compiler')
            if result.returncode:
                failures.append('xcodebuild -downloadComponent MetalToolchain')
    if shutil.which('dotnet', path=env['PATH']):
        result = subprocess.run(['dotnet', '--list-sdks'], env=env, capture_output=True, text=True)
        if result.returncode or not any(line.startswith('10.') for line in result.stdout.splitlines()):
            failures.append('Install .NET SDK 10 (the extraction and shader tools target net10.0).')
    if failures:
        print('\nComplete these steps, then run this check again:')
        for instruction in dict.fromkeys(failures):
            print('  ' + instruction)
        return 1
    print('\nPreparation tools are ready. Game compatibility still requires a device test.')
    return 0


def generate_catalog(destination):
    entries = []
    for path in sorted((REPO / 'dm/games').glob('*/game.tsv')):
        rows = [line.split('\t') for line in path.read_text().splitlines() if line and not line.startswith('#')]
        values = {row[0]: row[1] for row in rows if len(row) >= 2}
        versions = list(dict.fromkeys(row[2] for row in rows if row[0] == 'build' and len(row) >= 3))
        entries.append(dict(titleID=path.parent.name, name=values['name'], versions=versions))
    entries.sort(key=lambda entry: entry['name'].casefold())
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + '\n')
    print(f'{len(entries)} upstream profiles written to {destination}')
    return 0


def preparation_command(folder, keys, *, xcode=False, output=None, bundle_id=None):
    folder, keys = Path(folder).expanduser().resolve(), Path(keys).expanduser().resolve()
    if not folder.is_dir():
        raise ValueError('Choose a folder containing one game’s NSP/XCI files.')
    if folder == REPO or REPO in folder.parents or keys == REPO or REPO in keys.parents:
        raise ValueError('Keep games and keys outside the source repository.')
    if not keys.is_file() or keys.stat().st_size == 0:
        raise ValueError('Choose a nonempty prod.keys file; never paste its contents.')
    if not any(p.is_file() and p.suffix.lower() in ('.nsp', '.xci', '.nsz', '.xcz') for p in folder.iterdir()):
        raise ValueError('No NSP/XCI files found in the chosen folder.')
    # A bounded initial estimate: upstream performs additional stage-specific disk checks.
    size = sum(p.stat().st_size for p in folder.iterdir() if p.is_file() and p.suffix.lower() in ('.nsp', '.xci', '.nsz', '.xcz'))
    if shutil.disk_usage(folder).free < size * 2 + 10 * 1024**3:
        raise ValueError('Free about twice the game files’ size plus 10 GB on the game drive first.')
    command = [sys.executable, str(REPO / 'scripts/build_ipa_from_nsp.py'), str(folder), '--keys', str(keys), '--iswitch-card']
    if xcode:
        command.append('--prepare-xcode')
    if bundle_id:
        command += ['--bundle-id', bundle_id]
    if output:
        if xcode:
            raise ValueError('--output is for IPA builds; omit it with --xcode.')
        destination = Path(output).expanduser().resolve()
        if destination == REPO or REPO in destination.parents:
            raise ValueError('Keep generated game apps outside the source repository.')
        command += ['--out', str(destination)]
    return folder, command


def prepare(args):
    folder, command = preparation_command(args.folder, args.keys, xcode=args.xcode, output=args.output, bundle_id=getattr(args, 'bundle_id', None))
    if doctor():
        return 1
    # flock is automatically released after a crash. Never unlink the lock inode: a
    # second waiter could otherwise lock a different file while an existing run owns it.
    with (folder / '.iswitch-build.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('This game folder already has a preparation in progress.', file=sys.stderr)
            return 1
        env = tool_environment()
        if getattr(args, 'system_data', None):
            resources = Path(args.system_data).expanduser().resolve()
            if not resources.is_dir(): raise ValueError('system-data folder is unavailable')
            env['DM_SYSTEM_DATA'] = str(resources)
        result = subprocess.run(command, cwd=REPO, env=env)
    if result.returncode == 0:
        print('\nInstall the prepared game app, then AirDrop its .iswitch card to your iPhone.')
    return result.returncode


def wizard():
    if platform.system() != 'Darwin':
        raise ValueError('The file-picker assistant requires a Mac.')
    # These are constant AppleScript programs. User paths never become AppleScript or shell code.
    choices = []
    for script in ['POSIX path of (choose folder with prompt "Choose the folder containing one game’s NSP/XCI files")',
                   'POSIX path of (choose file with prompt "Choose your prod.keys file")']:
        result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
        if result.returncode:
            print('Preparation cancelled.'); return 0
        choices.append(result.stdout.rstrip('\n'))
    return prepare(argparse.Namespace(folder=choices[0], keys=choices[1], xcode=True, output=None))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('doctor', help='Check Mac preparation tools without changing the system')
    commands.add_parser('wizard', help='Choose a game folder and keys using native Mac dialogs; prepare for Xcode')
    key = commands.add_parser('import-keys', help='Import a prod.keys file or key ZIP into your private game workspace')
    key.add_argument('source'); key.add_argument('--output', required=True)
    firmware = commands.add_parser('firmware', help='Validate a firmware ZIP and extract optional system resources')
    firmware.add_argument('source'); firmware.add_argument('--keys', required=True); firmware.add_argument('--output', required=True)
    catalog = commands.add_parser('catalog', help='Refresh the app’s offline profile list')
    catalog.add_argument('--output', default=REPO / 'launcher/Resources/catalog.json')
    build = commands.add_parser('prepare', help='Prepare one game and export its reSwitch card')
    build.add_argument('folder')
    build.add_argument('--keys', required=True)
    build.add_argument('--xcode', action='store_true', help='Generate an Xcode workspace for your development team')
    build.add_argument('--output', help='Optional unsigned IPA output path')
    build.add_argument('--system-data', help='Optional system-data folder produced by the firmware command')
    build.add_argument('--bundle-id', help='Unique app identifier for your developer team, such as com.yourname.iswitch.mario')
    args = parser.parse_args(argv)
    try:
        if args.command == 'doctor': return doctor()
        if args.command == 'catalog': return generate_catalog(args.output)
        if args.command == 'wizard': return wizard()
        if args.command in ('import-keys', 'firmware'):
            destination = Path(args.output).expanduser().resolve()
            if destination == REPO or REPO in destination.parents:
                raise ValueError('keys and firmware must stay outside the source repository')
            if args.command == 'import-keys':
                count = iswitch_assets.import_keys(args.source, destination)
                print(f'Imported prod.keys with {count} entries. Key values were not logged.'); return 0
            result = iswitch_assets.prepare_firmware(args.source, args.keys, destination, REPO, tool_environment())
            print(f'Prepared {len(result["systemDataIDs"])} system resource archives in {destination / "system-data"}. Firmware programs are not executed by nxnative.'); return 0
        return prepare(args)
    except (ValueError, OSError) as error:
        print(f'Could not prepare game: {error}', file=sys.stderr); return 1
    except KeyboardInterrupt:
        print('\nPreparation interrupted. Rerun to reuse completed stages.', file=sys.stderr); return 130


if __name__ == '__main__':
    sys.exit(main())
