"""MonitorCache unit tests: char-budget eviction, identity/shrink invalidation, families.

Exercises the class directly (fresh instances, not the module-level CACHE), so no
cache hygiene between tests is needed.
"""
import prompts


def entry(chars):
    return {"chars": chars, "texto": "x" * chars}


def test_eviction_oldest_first_and_counter():
    c = prompts.MonitorCache(max_chars=10)
    c.put_prompt("a", (1, 1), 100, entry(5))
    c.put_prompt("b", (1, 2), 100, entry(5))
    c.put_prompt("c", (1, 3), 100, entry(5))   # 15 chars > 10 -> evicts "a" (oldest)
    assert c.get_prompt("a", (1, 1), 100) is None
    assert c.get_prompt("b", (1, 2), 100) is not None
    assert c.get_prompt("c", (1, 3), 100) is not None
    assert c._prompt_chars == 10


def test_identity_mismatch_misses():
    c = prompts.MonitorCache(max_chars=100)
    c.put_prompt("k", (1, 1), 50, entry(5))
    assert c.get_prompt("k", (2, 2), 50) is None       # another inode -> re-read
    assert c.get_prompt("k", (1, 1), 50) is not None


def test_shrunk_file_misses():
    c = prompts.MonitorCache(max_chars=100)
    c.put_prompt("k", (1, 1), 50, entry(5))
    assert c.get_prompt("k", (1, 1), 49) is None       # shrank -> rewritten -> re-read
    assert c.get_prompt("k", (1, 1), 51) is not None   # grew (append) -> still valid


def test_families_signature_gate():
    c = prompts.MonitorCache(max_chars=100)
    fams = [{"n": 2}]
    c.put_families("run", ("a", "b"), fams)
    assert c.get_families("run", ("a", "b")) is fams   # same signature -> same object
    assert c.get_families("run", ("a", "b", "c")) is None  # spawn/removal invalidates


def test_empty_cache_resets_counter():
    c = prompts.MonitorCache(max_chars=100)
    c.put_prompt("a", (1, 1), 10, entry(3))
    c.put_prompt("b", (1, 2), 10, entry(4))
    c.drop_prompt("a")
    c.drop_prompt("b")
    assert c._prompt_chars == 0                        # no entries -> nothing to count
