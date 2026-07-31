"""Parity tripwire between the launchers (POSIX and PowerShell).

It only reads the TEXT of monitor-app.sh and start-monitor.ps1 and checks that
the canonical flags exist in both. If someone adds or renames a flag in one
launcher and forgets the other, this fails pointing at the one left behind.
It does not validate behavior: that is what actually running the launchers is for.
"""
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def sh():
    return (REPO_ROOT / "monitor-app.sh").read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def ps1():
    return (REPO_ROOT / "workflow-monitor" / "start-monitor.ps1").read_text(encoding="utf-8")


# (PowerShell name, POSIX long flag). The .sh also accepts the Windows -<Name>
# alias in its case block (parity documented in its own header).
CANONICAL_FLAGS = [
    ("Port", "--port"),
    ("NoBrowser", "--no-browser"),
    ("Restart", "--restart"),
    ("Stop", "--stop"),
]


@pytest.mark.parametrize("ps_flag,sh_flag", CANONICAL_FLAGS, ids=[c[0] for c in CANONICAL_FLAGS])
def test_canonical_flag_in_both_launchers(ps_flag, sh_flag, sh, ps1):
    assert f"${ps_flag}" in ps1, f"start-monitor.ps1 lost the -{ps_flag} parameter"
    assert sh_flag in sh, f"monitor-app.sh lost the {sh_flag} flag"
    assert f"-{ps_flag}" in sh, (
        f"monitor-app.sh lost the -{ps_flag} alias (parity with the Windows launcher)")


def test_sh_help_documents_the_flags(sh):
    # --help is the visible surface: a flag that exists but is undocumented is half-drifted.
    for f in ("--port", "--no-browser", "--restart", "--stop"):
        assert sh.count(f) >= 2, f"{f} exists but does not show up in monitor-app.sh --help"
