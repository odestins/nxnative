"""Merge shared iCloud save capabilities without losing the memory entitlement."""
import plistlib
import re
import sys
from pathlib import Path

path, container = Path(sys.argv[1]), sys.argv[2]
if not re.fullmatch(r'iCloud\.[A-Za-z0-9.-]+', container):
    raise SystemExit('Invalid iCloud container identifier')
data = plistlib.loads(path.read_bytes())
data.update({
    'com.apple.developer.icloud-container-identifiers': [container],
    'com.apple.developer.ubiquity-container-identifiers': [container],
    'com.apple.developer.icloud-services': ['CloudDocuments'],
    'com.apple.developer.ubiquity-kvstore-identifier': '$(TeamIdentifierPrefix)' + container.removeprefix('iCloud.'),
})
path.write_bytes(plistlib.dumps(data))
