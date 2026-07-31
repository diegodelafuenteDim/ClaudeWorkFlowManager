"""Makes the workflow-monitor modules importable from the tests.

They live in workflow-monitor/ (hyphenated directory, not a package), so the
directory goes on sys.path and the modules are imported flat (fsread, prompts,
api, server) — the same layout server.py sees when run as a script. Tests that
touch ROOT monkeypatch it on fsread (the single owner): api reads it as
fsread.ROOT attribute, so one patch covers every consumer.
"""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "workflow-monitor"))
