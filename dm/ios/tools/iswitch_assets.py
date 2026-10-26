"""Validate/import user keys and firmware outside the repository; never execute archive files."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile


def validate_keys(data):
    if len(data) > 256 * 1024:
        raise ValueError('key file exceeds 256 KB')
    try:
        text = data.decode('utf-8-sig')
    except UnicodeDecodeError:
        raise ValueError('prod.keys must be a text file') from None
    values = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'([a-zA-Z0-9_]+)\s*=\s*([a-fA-F0-9]{32,4096})', line)
        if not match or len(match[2]) % 2:
            raise ValueError('invalid key file format; no key contents were logged')
        if match[1] in values and values[match[1]] != match[2]:
            raise ValueError('conflicting duplicate entries in key file')
        values[match[1]] = match[2]
    if len(values.get('header_key', '')) != 64:
        raise ValueError('prod.keys is missing a valid header_key')
    return len(values)


def import_keys(source, destination):
    source, destination = Path(source), Path(destination)
    if source.suffix.lower() == '.zip':
        with zipfile.ZipFile(source) as archive:
            matches = [entry for entry in archive.infolist() if PurePosixPath(entry.filename).name == 'prod.keys' and not entry.is_dir()]
            if len(matches) != 1 or matches[0].file_size > 256 * 1024:
                raise ValueError('key archive must contain exactly one prod.keys file, at most 256 KB')
            with archive.open(matches[0]) as stream:
                data = stream.read(256 * 1024 + 1)
    else:
        with source.open('rb') as stream:
            data = stream.read(256 * 1024 + 1)
    count = validate_keys(data)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.keys-', dir=destination.parent)
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(data); output.flush(); os.fsync(output.fileno())
        os.chmod(temp, 0o600)
        os.replace(temp, destination)
    finally:
        if os.path.exists(temp): os.unlink(temp)
    return count


def firmware_entries(archive):
    entries = [entry for entry in archive.infolist() if not entry.is_dir()]
    if not entries or len(entries) > 4096:
        raise ValueError('firmware archive must contain 1–4096 NCA files')
    seen = set()
    for entry in entries:
        path = PurePosixPath(entry.filename)
        mode = entry.external_attr >> 16
        if path.is_absolute() or '..' in path.parts or '\\' in entry.filename or stat.S_ISLNK(mode):
            raise ValueError('unsafe archive path or symbolic link')
        if not re.fullmatch(r'[0-9a-fA-F]{32}(?:\.cnmt)?\.nca', path.name):
            raise ValueError('firmware archive contains a non-NCA file; no installers or scripts are accepted')
        if path.name.lower() in seen:
            raise ValueError('duplicate firmware NCA filename')
        seen.add(path.name.lower())
        if entry.file_size < 0x400 or entry.file_size > 2 * 1024**3 or entry.flag_bits & 1:
            raise ValueError('invalid, oversized, or password-protected firmware file')
    total = sum(entry.file_size for entry in entries)
    if total > 8 * 1024**3:
        raise ValueError('firmware archive exceeds 8 GB uncompressed')
    return entries, total


def prepare_firmware(source, keys, destination, repo, env):
    source, keys, destination, repo = map(Path, (source, keys, destination, repo))
    if destination.exists():
        raise ValueError('firmware output already exists; use a new version folder to preserve the old one')
    with keys.open('rb') as stream:
        validate_keys(stream.read(256 * 1024 + 1))
    with zipfile.ZipFile(source) as archive:
        entries, total = firmware_entries(archive)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if shutil.disk_usage(destination.parent).free < total * 3 + 1024**3:
            raise ValueError('insufficient free space for firmware preparation')
        temporary = Path(tempfile.mkdtemp(prefix='.firmware-', dir=destination.parent))
        try:
            ncas = temporary / 'nca'; ncas.mkdir()
            for entry in entries:
                with archive.open(entry) as src, (ncas / PurePosixPath(entry.filename).name).open('wb') as dst:
                    shutil.copyfileobj(src, dst, length=1024 * 1024)
            tool = temporary / 'tools'
            logs = temporary / 'logs'; logs.mkdir()
            with (logs / 'build.log').open('w') as log:
                result = subprocess.run(['dotnet', 'publish', str(repo / 'dm/tools/nx_extract/nx_extract.csproj'),
                                         '-c', 'Release', '-o', str(tool),
                                         f'-p:BaseIntermediateOutputPath={temporary}/obj/',
                                         f'-p:BaseOutputPath={temporary}/bin/'], env=env, stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                raise ValueError(f'firmware extraction tool failed to build; log: {logs / "build.log"}')
            output = temporary / 'system-data'
            with (logs / 'extract.log').open('w') as log:
                result = subprocess.run(['dotnet', str(tool / 'nx_extract.dll'), str(keys), '--system-data', str(ncas), str(output)], env=env, stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                raise ValueError(f'firmware resource extraction failed; log: {logs / "extract.log"}')
            with source.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            manifest = dict(schemaVersion=1, archiveSHA256=digest, ncaCount=len(entries),
                            systemDataIDs=sorted(p.name for p in output.iterdir() if p.is_dir()))
            (temporary / 'firmware.json').write_text(json.dumps(manifest, indent=2) + '\n')
            # Keep logs and resources; encrypted NCAs and compiler intermediates can be recreated.
            for name in ['nca', 'tools', 'obj', 'bin']:
                shutil.rmtree(temporary / name, ignore_errors=True)
            os.replace(temporary, destination)
            return manifest
        except Exception:
            # Keep diagnostic logs for a failed attempt, but never copy the key file.
            raise
