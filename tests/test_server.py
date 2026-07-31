"""Tests for the pure parsers behind the monitor's endpoints.

They do not start the server: they exercise the functions that translate the
on-disk state (journal.jsonl, agent-*.jsonl, workflow scripts) into what the
endpoints serve. The odd cases come from real regressions documented in the
code comments. Asserted JSON keys and state values are the Spanish API
contract and stay verbatim.
"""
import json
import time

import api
import fsread
import prompts


def write_agent(directory, agent_id, prompt="Sos el agente de prueba."):
    """Minimal agent-<id>.jsonl: line 0 = user event carrying the prompt."""
    line0 = {"type": "user", "timestamp": "2026-07-31T12:00:00Z", "cwd": "c:/x",
             "gitBranch": "main", "slug": "prueba", "version": "1.0",
             "message": {"content": prompt}}
    f = directory / f"agent-{agent_id}.jsonl"
    f.write_text(json.dumps(line0) + "\n", encoding="utf-8")
    return f


# ---------------------------------------------------------------- pure helpers

def test_clean_project_slug():
    # Claude Code slugs on the three OSes + a name that is not a slug.
    assert fsread.clean_project_slug("c--Net-8-Tools") == "Tools"
    assert fsread.clean_project_slug("C--MiApp") == "MiApp"
    assert fsread.clean_project_slug("-home-diego-repos-miapp") == "repos-miapp"
    assert fsread.clean_project_slug("-Users-diego-dev-app") == "dev-app"
    assert fsread.clean_project_slug("proyecto-suelto") == "proyecto-suelto"


def test_unescape():
    assert fsread.unescape("hola\\nmundo") == "hola mundo"
    assert fsread.unescape('dijo \\"hola\\"') == 'dijo "hola"'
    assert fsread.unescape("c:\\\\ruta") == "c:\\ruta"


def test_strip_boilerplate():
    f = fsread._strip_boilerplate
    # Context sentence with a path (Windows and POSIX): skipped.
    assert f("Repo: c:\\Net 8\\App (rama main). Sos el auditor.") == "Sos el auditor."
    assert f("Repo: /home/diego/app (rama main). Sos el auditor.") == "Sos el auditor."
    # Two context sentences in a row.
    assert f("Repo: c:\\X. Workdir: c:\\Y. Sos el auditor.") == "Sos el auditor."
    # Label that only the old inline copy in agent_mission knew: now unified.
    assert f("Contexto: c:\\Net 8\\App. Sos el auditor.") == "Sos el auditor."
    # A normal sentence is left alone.
    text = "Analiza el modulo de pagos. Reporta bugs."
    assert f(text) == text
    # 100% boilerplate line -> "" (the caller moves on to the next line).
    assert f("Workdir: c:\\Net 8\\App") == ""


def test_title_of():
    # Decoration or path-context lines are skipped; the first line with content wins.
    assert prompts.title_of("###\nSos el auditor de pagos.\nresto") == "Sos el auditor de pagos."
    assert prompts.title_of("Repo: c:\\X (rama main).\nSos el auditor.\n") == "Sos el auditor."
    # Pin of the unified label set: 'Contexto' (only the old agent_mission copy knew it)
    # now strips here too, even without a path in the sentence.
    assert prompts.title_of("Contexto: preparando el entorno.\nSos el auditor.\n") == "Sos el auditor."
    assert len(prompts.title_of("x" * 500)) <= 110


def test_search_pattern():
    # Case-insensitive without re.IGNORECASE (hand-built [Aa] class).
    p = prompts.search_pattern("hola")
    assert p.search("decir HOLA fuerte")
    assert p.search("Hola")
    assert not p.search("helado")
    # The query is escaped: parentheses and dots are literal.
    assert prompts.search_pattern("f(x)").search("calcular F(X) aca")
    assert not prompts.search_pattern("a.b").search("aXb")
    # U+0130 ('I' with dot): its .lower() is 2 code points -> goes literal, no crash.
    assert prompts.search_pattern("\u0130stanbul").search("\u0130stanbul")


# ---------------------------------------------------------------- journal and states

def test_journal_info(tmp_path):
    (tmp_path / "journal.jsonl").write_text(
        '{"type":"started","agentId":"aa11","key":"k1"}\n'
        '{"type":"result","agentId":"aa11","key":"k1"}\n'
        '{"type":"started","agentId":"bb22","key":"k2"}\n',
        encoding="utf-8")
    ji = fsread.journal_info(tmp_path)
    assert ji.key_by_agent == {"aa11": "k1", "bb22": "k2"}
    assert ji.done_agents == {"aa11"}
    assert ji.done_keys == {"k1"}
    assert ji.last_type == "started"


def test_journal_info_no_journal(tmp_path):
    # Tuple equality on purpose: freezes the NamedTuple's field order.
    assert fsread.journal_info(tmp_path) == ({}, set(), set(), None)


def test_run_status():
    now = time.time()
    old = now - 10 * api.RUN_ACTIVE_SECS
    assert api.run_status([{"mtime": now}], "started") == "ACTIVO"
    assert api.run_status([{"mtime": old}], "result") == "TERMINADO"
    assert api.run_status([{"mtime": old}], "started") == "ESTANCADO"
    assert api.run_status([], None) == "ESTANCADO"


def test_find_run_dir_validates_ids(tmp_path, monkeypatch):
    # Ids come from the client and go into a glob: anything invalid dies BEFORE touching disk.
    monkeypatch.setattr(fsread, "ROOT", tmp_path)
    assert api.find_run_dir("") is None
    assert api.find_run_dir("../../etc") is None
    assert api.find_run_dir("wf_../x") is None
    assert api.find_run_dir("wf_noexiste") is None


# ---------------------------------------------------------------- prompts

def test_prompt_entry_and_api_prompt_shape(tmp_path):
    e = prompts.prompt_entry(write_agent(tmp_path, "ab12cd"))
    assert e["id"] == "ab12cd"
    assert e["texto"] == "Sos el agente de prueba."
    assert e["chars"] == len(e["texto"])
    assert e["truncado"] is False
    assert e["gitBranch"] == "main"
    # The shape of /api/prompt comes from this entry via _PROMPT_FIELDS: if a field
    # disappears from prompt_entry, it blows up here and not as "undefined" client-side.
    assert set(api._PROMPT_FIELDS) <= set(e)


def test_prompt_entry_unreadable(tmp_path):
    f = tmp_path / "agent-ffff.jsonl"
    f.write_text("esto no es json\n", encoding="utf-8")
    assert prompts.prompt_entry(f) is None
    f2 = tmp_path / "agent-eeee.jsonl"
    f2.write_text("", encoding="utf-8")
    assert prompts.prompt_entry(f2) is None


def test_agent_mission_skips_boilerplate(tmp_path):
    # Line 0 is not a valid user event, but has a "content" match with boilerplate in
    # front: agent_mission (the raw fallback) skips it via the canonical stripper.
    f = tmp_path / "agent-aaaa.jsonl"
    f.write_text('{"content":"Repo: c:\\\\Net 8\\\\App (rama main). Analiza pagos."}\n',
                 encoding="utf-8")
    assert fsread.agent_mission(f) == "Analiza pagos."[:70]
    # Whole line is boilerplate -> "?" (better than showing the repo path as the mission).
    f2 = tmp_path / "agent-bbbb.jsonl"
    f2.write_text('{"content":"Workdir: c:\\\\Net 8\\\\App"}\n', encoding="utf-8")
    assert fsread.agent_mission(f2) == "?"


# ---------------------------------------------------------------- workflow plan

def test_parse_plan():
    src = """export const meta = {
  name: 'demo',
  description: "Un plan de prueba",   // comentario al final
  phases: [
    { title: 'Fase 1', detail: 'detalle', },
    { title: "Fase 2" },
  ],
}
phase('Fase 1')"""
    plan = fsread.parse_plan(src)
    assert plan["nombre"] == "demo"
    assert plan["descripcion"] == "Un plan de prueba"
    assert [f["titulo"] for f in plan["fases"]] == ["Fase 1", "Fase 2"]
    assert plan["fases"][0]["detalle"] == "detalle"


def test_parse_plan_no_meta():
    assert fsread.parse_plan("const x = 1") is None
    assert fsread.parse_plan("") is None
    assert fsread.parse_plan(None) is None


# ---------------------------------------------------------------- /api/runs end to end

def test_api_runs_integration(tmp_path, monkeypatch):
    monkeypatch.setattr(fsread, "ROOT", tmp_path)
    # A workflow run with its agent finished...
    wf = tmp_path / "c--Net-8-Demo" / "sesion1234abcd" / "subagents" / "workflows" / "wf_abc123"
    wf.mkdir(parents=True)
    (wf / "journal.jsonl").write_text(
        '{"type":"started","agentId":"aa11","key":"k1"}\n'
        '{"type":"result","agentId":"aa11","key":"k1"}\n',
        encoding="utf-8")
    write_agent(wf, "aa11")
    # ...and a loose agent in another session.
    loose = tmp_path / "c--Net-8-Demo" / "sesionffff9999" / "subagents"
    loose.mkdir(parents=True)
    write_agent(loose, "bb22")

    rows = api.api_runs()
    # Freezes the JSON contract of a /api/runs row.
    for r in rows:
        assert set(r) == {"run", "workflow", "proyecto", "sesion", "agentes",
                          "listos", "estado", "ultimaAct", "edadSeg"}
    by_run = {r["run"]: r for r in rows}
    assert set(by_run) == {"wf_abc123", "sueltos_sesionffff9999"}

    wf_row = by_run["wf_abc123"]
    assert wf_row["proyecto"] == "Demo"           # slug c--Net-8-Demo cleaned
    assert wf_row["agentes"] == 1
    assert wf_row["listos"] == 1                  # the journal has its result
    assert wf_row["estado"] == "ACTIVO"           # just written to disk

    loose_row = by_run["sueltos_sesionffff9999"]
    assert loose_row["workflow"] == "(agentes sueltos)"
    assert loose_row["agentes"] == 1
    assert loose_row["estado"] == "ACTIVO"


def test_api_runs_missing_root(tmp_path, monkeypatch):
    # Freshly installed machine, no ~/.claude/projects: empty list, not a 500.
    monkeypatch.setattr(fsread, "ROOT", tmp_path / "no-existe")
    assert api.api_runs() == []
