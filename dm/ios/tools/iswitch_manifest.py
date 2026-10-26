"""Small, data-only game cards for reSwitch. Never includes keys or game binaries."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def launch_url(title_id):
    if not re.fullmatch(r'[0-9A-Fa-f]{16}', title_id):
        raise ValueError('invalid title ID')
    return f'nxnative-{title_id.lower()}://launch'


def write_card(destination, *, title_id, name, version, bundle_id, icon=None,
               profiled=True, packaged=True, revision=None):
    card = dict(schemaVersion=1, titleID=title_id.upper(), name=name,
                version=version or '1.0', bundleID=bundle_id,
                launchURL=launch_url(title_id),
                buildState='packaged' if packaged else 'project',
                compatibility='profiled' if profiled else 'experimental',
                minimumOS='26.0')
    if not name or len(name) > 200 or any(ord(c) < 32 for c in name):
        raise ValueError('invalid game name for reSwitch')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle_id):
        raise ValueError('invalid bundle ID for reSwitch')
    if revision:
        card['sourceRevision'] = revision
    if icon:
        with Path(icon).open('rb') as source:
            data = source.read(2_000_001)
        if len(data) > 2_000_000:
            raise ValueError('game cover exceeds 2 MB')
        card['artworkBase64'] = base64.b64encode(data).decode('ascii')
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.iswitch-', dir=destination.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as output:
            json.dump(card, output, ensure_ascii=False, indent=2)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return destination


def source_revision(repo):
    try:
        return subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None
