#!/usr/bin/env python3
"""Verify the vendored SukiSU effect/gesture implementation, allowing package relocation only."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
vendor = root / 'android/app/src/main/kotlin/com/retrsoft/nuistaio/navigation/sukisu'
manifest = json.loads((vendor / 'UPSTREAM.json').read_text())
for entry in manifest['files']:
    path = vendor / entry['source']
    restored = path.read_text().replace('com.retrsoft.nuistaio.navigation.sukisu', 'com.sukisu.ultra.ui')
    actual = hashlib.sha256(restored.encode()).hexdigest()
    if actual != entry['sha256']:
        raise SystemExit(f'Changed upstream implementation: {entry["source"]}')
print(f'Verified {len(manifest["files"])} upstream files: package relocation only.')
