"""Run the pinned require-no-mistakes verify.py with inputs resolved from the real workflow YAML."""
import json, os, re, subprocess, sys, tempfile, yaml

wf_path, action_dir = sys.argv[1], sys.argv[2]
wf = yaml.safe_load(open(wf_path))
step = next(s for s in wf["jobs"]["check"]["steps"] if "require-no-mistakes" in s.get("uses", ""))
action = yaml.safe_load(open(os.path.join(action_dir, "action.yml")))

def resolve(value, repo_vars):
    # GitHub Actions: an unset `vars.X` context evaluates to an empty string.
    return re.sub(r"\$\{\{\s*vars\.(\w+)\s*\}\}", lambda m: repo_vars.get(m.group(1), ""), str(value))

def run(label, author, head_ref, repo_vars):
    inputs = {k: v.get("default", "") for k, v in action["inputs"].items()}
    inputs["github-token"] = ""  # offline: no live lookup
    inputs.update({k: resolve(v, repo_vars) for k, v in step["with"].items()})
    env_map = action["runs"]["steps"][0]["env"]
    env = {"PATH": os.environ["PATH"]}
    for name, expr in env_map.items():
        key = re.search(r"inputs\.([\w-]+)", expr).group(1)
        env[name] = inputs[key]
    with tempfile.TemporaryDirectory() as d:
        ev = os.path.join(d, "event.json"); out = os.path.join(d, "out")
        json.dump({"pull_request": {"number": 42, "body": "plain PR body, no attestation",
                   "user": {"login": author}, "head": {"ref": head_ref, "sha": "a" * 40}}}, open(ev, "w"))
        env.update(GITHUB_EVENT_PATH=ev, GITHUB_OUTPUT=out, GITHUB_ACTION_PATH=action_dir)
        p = subprocess.run([sys.executable, os.path.join(action_dir, "verify.py")], env=env, capture_output=True, text=True)
        outputs = dict(l.split("=", 1) for l in open(out).read().splitlines()) if os.path.exists(out) else {}
    verdict = "PASS (exempt)" if p.returncode == 0 and outputs.get("exempt") == "true" else f"FAIL (exit {p.returncode})"
    first = (p.stdout + p.stderr).strip().splitlines()[0] if (p.stdout + p.stderr).strip() else ""
    print(f"{label:<62} exempt-head-branches={inputs['exempt-head-branches']!r:<16} -> {verdict}\n    {first}")
    return verdict

print(f"workflow with: {step['with']}\n")
r = []
r.append(run("1. upstream-sync, author teammate, repo var UNSET", "teammate", "upstream-sync", {}))
r.append(run("2. upstream-sync, author teammate, var=upstream-sync", "teammate", "upstream-sync", {"NO_MISTAKES_EXEMPT_HEAD_BRANCHES": "upstream-sync"}))
r.append(run("3. feature branch, author teammate, var=upstream-sync", "teammate", "feature/x", {"NO_MISTAKES_EXEMPT_HEAD_BRANCHES": "upstream-sync"}))
r.append(run("4. upstream-sync-evil, author teammate, var=upstream-sync", "teammate", "upstream-sync-evil", {"NO_MISTAKES_EXEMPT_HEAD_BRANCHES": "upstream-sync"}))
r.append(run("5. feature branch, author FrostyFitz, var UNSET", "FrostyFitz", "feature/x", {}))
r.append(run("6. feature branch, author someone-else, var UNSET", "someone-else", "feature/x", {}))
