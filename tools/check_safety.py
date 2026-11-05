"""Run before connecting Rojo. Fails if Rojo could delete Studio content or the tree looks partial.

Every folder and script must set ignoreUnknownInstances, or Rojo deletes
Studio children it does not know about (assets, ScreenGuis, MeshParts).
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MINIMUMS = {"lobby": 103, "game": 146}
errors = []

def ignores(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f).get("ignoreUnknownInstances") is True
    except (OSError, ValueError):
        return False

def walk_project(node, where):
    for key, value in node.items():
        if key.startswith("$") or not isinstance(value, dict):
            continue
        if value.get("$ignoreUnknownInstances") is not True:
            errors.append(f"{where}/{key}: missing $ignoreUnknownInstances")
        walk_project(value, f"{where}/{key}")

for place, minimum in MINIMUMS.items():
    base = os.path.join(ROOT, "places", place)
    with open(os.path.join(base, "default.project.json"), encoding="utf-8") as f:
        project = json.load(f)
    if not project.get("servePlaceIds"):
        errors.append(f"{place}: servePlaceIds is empty")
    walk_project(project["tree"], place)
    count = 0
    src = os.path.join(base, "src")
    for dirpath, _, files in os.walk(src):
        if dirpath != src and not ignores(os.path.join(dirpath, "init.meta.json")):
            errors.append(f"{dirpath}: missing init.meta.json with ignoreUnknownInstances")
        for name in files:
            if not name.endswith(".luau"):
                continue
            count += 1
            stem = name[:-5]
            for suffix in (".server", ".client"):
                stem = stem.removesuffix(suffix)
            if not ignores(os.path.join(dirpath, stem + ".meta.json")):
                errors.append(f"{dirpath}/{name}: missing {stem}.meta.json with ignoreUnknownInstances")
    if count < minimum:
        errors.append(f"{place}: {count} scripts, expected at least {minimum}. Tree looks partial")
    print(f"{place}: {count} scripts")

for e in errors:
    print("ERROR", e)
print("FAILED, do not connect" if errors else "OK")
sys.exit(1 if errors else 0)
