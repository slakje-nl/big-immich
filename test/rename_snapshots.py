#!/usr/bin/env python3
"""Rename exported xcresult attachments to their human-readable names.

`xcrun xcresulttool export attachments` writes files under opaque UUID names
and only records the friendly name in manifest.json. This renames the numbered
journey snapshots (e.g. 03-settings-configured.png) so the folder is browsable.
"""

import json
import os
import re
import sys

base = sys.argv[1] if len(sys.argv) > 1 else "test/snapshots"
manifest = os.path.join(base, "manifest.json")

if not os.path.exists(manifest):
    sys.exit(0)

with open(manifest) as f:
    data = json.load(f)


def walk(node):
    if isinstance(node, dict):
        exported = node.get("exportedFileName")
        suggested = node.get("suggestedHumanReadableName")
        if exported and suggested and re.match(r"^\d\d-", suggested):
            clean = suggested.split("_0_")[0] + os.path.splitext(suggested)[1]
            src = os.path.join(base, exported)
            dst = os.path.join(base, clean)
            if os.path.exists(src) and not os.path.exists(dst):
                os.rename(src, dst)
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)


walk(data)
