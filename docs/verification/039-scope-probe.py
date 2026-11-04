"""Behavioural RED→GREEN probe for skills.write_approval_scope.

Run with the tree under test on PYTHONPATH:
    PYTHONPATH=/tmp/gen-v0227 /opt/hermes/.venv/bin/python /tmp/scope_probe.py
Assertions target the WANTED behaviour, so the pristine tree fails (no `mutations` kwarg, and
every mutation gets staged) and the patched tree passes.
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
except TypeError as exc:
    out["create_staged"] = f"TypeError: {exc}"

res = json.loads(skill_manage(action="patch", name="demo-skill",
                              old_string="Body line.", new_string="Body line edited."))
out["patch_e2e"] = {k: res.get(k) for k in ("success", "staged", "pending_id")}
out["file_after"] = "edited" in (sk / "SKILL.md").read_text(encoding="utf-8")

res2 = json.loads(skill_manage(action="create", name="new-skill",
                               content="---\nname: new-skill\ndescription: d\n---\n\nx\n"))
out["create_e2e"] = {k: res2.get(k) for k in ("success", "staged", "pending_id")}
out["new_skill_on_disk"] = (home / "skills" / "new-skill" / "SKILL.md").exists()

out["memory_staged"] = not wa.evaluate_gate(wa.MEMORY).allow

print(json.dumps(out, ensure_ascii=False, indent=2))

expected = {
    "patch_allow": True,
    "create_staged": True,
    "skillmd_staged": True,
    "ref_allow": True,
    "delete_staged": True,
    "batch_mixed_staged": True,
    "patch_e2e": {"success": True, "staged": None, "pending_id": None},
    "file_after": True,
    "create_e2e": {"success": True, "staged": True},
    "new_skill_on_disk": False,
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
