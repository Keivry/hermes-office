"""Behavioural RED→GREEN probe for skills.write_approval_scope (flat + batch shapes).

Run with the tree under test on PYTHONPATH:
    PYTHONPATH=/tmp/vfy /opt/hermes/.venv/bin/python 039-scope-probe.py

Assertions target the WANTED behaviour, so a pristine tree fails (no `mutations` kwarg, and
every mutation gets staged) and the patched tree passes.

The batch block matters: `operations=[...]` is the shape the tool schema advertises, and it
returns early from `skill_manage()` into `tools/skill_manager_batch.py`, which has its own
`_run_write_gate()` call. A patch that only wires the flat path passes every flat assertion
and still stages every batch -- that gap shipped once and was caught by a live call, so the
batch assertions are the regression guard.
"""
import json
import os
import pathlib
import tempfile

root = pathlib.Path(tempfile.mkdtemp(prefix="scope-"))
home = root / "home"
(home / "skills").mkdir(parents=True)
(home / "config.yaml").write_text(
    "memory:\n  write_approval: true\nskills:\n  write_approval: true\n  write_approval_scope: create\n", encoding="utf-8")
os.environ["HERMES_HOME"] = str(home)

sk = home / "skills" / "demo-skill"
sk.mkdir()
(sk / "SKILL.md").write_text(
    "---\nname: demo-skill\ndescription: demo\n---\n\nBody line.\n", encoding="utf-8")

from tools import write_approval as wa  # noqa: E402
from tools.skill_manager_tool import skill_manage  # noqa: E402

out = {}


def gate(mutations):
    return wa.evaluate_gate(wa.SKILLS, mutations=mutations)


def e2e(res):
    d = json.loads(res)
    return {k: d.get(k) for k in ("success", "staged", "pending_id")}


try:
    out["patch_allow"] = gate([{"action": "patch", "name": "demo-skill"}]).allow
except TypeError as exc:
    out["patch_allow"] = f"TypeError: {exc}"

try:
    out["create_staged"] = not gate([{"action": "create", "name": "new-skill"}]).allow
    out["skillmd_staged"] = not gate(
        [{"action": "write_file", "name": "demo-skill", "file_path": "SKILL.md"}]).allow
    out["ref_allow"] = gate(
        [{"action": "write_file", "name": "demo-skill", "file_path": "references/x.md"}]).allow
    out["delete_staged"] = not gate([{"action": "delete", "name": "demo-skill"}]).allow
    out["batch_mixed_staged"] = not gate(
        [{"action": "patch", "name": "demo-skill"},
         {"action": "create", "name": "another"}]).allow
    out["batch_patch_allow"] = gate(
        [{"action": "patch", "name": "demo-skill"},
         {"action": "patch", "name": "demo-skill"}]).allow
except TypeError as exc:
    out["create_staged"] = f"TypeError: {exc}"

# flat shape
res = json.loads(skill_manage(action="patch", name="demo-skill",
                              old_string="Body line.", new_string="Body line edited."))
out["patch_e2e"] = {k: res.get(k) for k in ("success", "staged", "pending_id")}
out["file_after"] = "edited" in (sk / "SKILL.md").read_text(encoding="utf-8")

res2 = json.loads(skill_manage(action="create", name="new-skill",
                               content="---\nname: new-skill\ndescription: d\n---\n\nx\n"))
out["create_e2e"] = {k: res2.get(k) for k in ("success", "staged", "pending_id")}
out["new_skill_on_disk"] = (home / "skills" / "new-skill" / "SKILL.md").exists()

# batch shape -- the advertised call shape; must honour the same scope
out["batch_patch_e2e"] = e2e(skill_manage(action="batch", name="", operations=[
    {"action": "patch", "name": "demo-skill",
     "old_string": "Body line edited.", "new_string": "Body line edited twice."}]))
out["batch_file_after"] = "twice" in (sk / "SKILL.md").read_text(encoding="utf-8")

out["batch_create_e2e"] = e2e(skill_manage(action="batch", name="", operations=[
    {"action": "create", "name": "batch-new",
     "content": "---\nname: batch-new\ndescription: d\n---\n\ny\n"}]))
out["batch_new_on_disk"] = (home / "skills" / "batch-new" / "SKILL.md").exists()

out["memory_staged"] = not wa.evaluate_gate(wa.MEMORY).allow

print(json.dumps(out, ensure_ascii=False, indent=2))

expected = {
    "patch_allow": True,
    "create_staged": True,
    "skillmd_staged": True,
    "ref_allow": True,
    "delete_staged": True,
    "batch_mixed_staged": True,
    "batch_patch_allow": True,
    "patch_e2e": {"success": True, "staged": None, "pending_id": None},
    "file_after": True,
    "create_e2e": {"success": True, "staged": True},
    "new_skill_on_disk": False,
    "batch_patch_e2e": {"success": True, "staged": None, "pending_id": None},
    "batch_file_after": True,
    "batch_create_e2e": {"success": True, "staged": True},
    "batch_new_on_disk": False,
    "memory_staged": True,
}


def _matches(exp, got):
    if isinstance(exp, dict) and isinstance(got, dict):
        return all(got.get(k) == v for k, v in exp.items())
    return got == exp


fails = [k for k, v in expected.items() if not _matches(v, out.get(k))]
if fails:
    print("\nFAILED:", fails)
    raise SystemExit(1)
print("\nALL GREEN")
