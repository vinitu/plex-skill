#!/usr/bin/env python3
"""Compatibility CLI for the Plex skill.

Preserves the published public entrypoint while delegating execution to the
shell runtime introduced under scripts/commands/ and scripts/lib/.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys


def main() -> int:
    script_dir = pathlib.Path(__file__).resolve().parent
    runtime = script_dir / "lib" / "plex_runtime.sh"
    completed = subprocess.run([str(runtime), *sys.argv[1:]])
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
