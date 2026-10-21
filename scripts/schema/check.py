#!/usr/bin/env python3
"""Check schema/parameters.json against itself and against the Terraform roots it fills.

Offline and read-only: no Terraform, Azure or network calls. Exit code 1 on any problem.
"""
import ipaddress
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHASES = ["discover", "prepare", "configure", "bootstrap", "deploy", "first_run", "verify", "handover"]
ASKING_PHASES = {"discover", "configure"}
TYPES = {"string", "int", "bool", "enum", "uuid", "cidr", "string_list", "ipv4_list", "group_list"}
FORM_LIMIT = 10

VARIABLE = re.compile(r'^variable\s+"([^"]+)"\s*\{', re.M)


def root_variables(stage_dir):
    """Map each variable declared in a root's .tf files to whether it has a default."""
    found = {}
    for tf in sorted(stage_dir.glob("*.tf")):
        text = tf.read_text()
        starts = [(m.start(), m.group(1)) for m in VARIABLE.finditer(text)]
        for i, (start, name) in enumerate(starts):
            end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
            found[name] = re.search(r"^\s*default\s*=", text[start:end], re.M) is not None
    return found


def check_default(p):
    """Problems with a parameter's concrete default against its own rules."""
    d = p.get("default")
    if d is None or (isinstance(d, str) and "{" in d):
        return []
    errs = []
    t = p["type"]
    if t == "int":
        if not isinstance(d, int) or isinstance(d, bool):
            errs.append("default is not an int")
        elif ("min" in p and d < p["min"]) or ("max" in p and d > p["max"]):
            errs.append("default is outside min/max")
    elif t == "bool" and not isinstance(d, bool):
        errs.append("default is not a bool")
    elif t == "cidr":
        try:
            net = ipaddress.ip_network(d)
        except ValueError:
            errs.append("default is not a CIDR block")
        else:
            if ("min_prefix" in p and net.prefixlen < p["min_prefix"]) or ("max_prefix" in p and net.prefixlen > p["max_prefix"]):
                errs.append("default prefix length is outside min_prefix/max_prefix")
    elif t == "enum":
        ok = [c["value"] for c in p.get("choices", []) if c.get("supported", True)]
        if d not in ok:
            errs.append("default is not a supported choice")
    if "pattern" in p and isinstance(d, str) and not re.fullmatch(p["pattern"], d):
        errs.append("default does not match pattern")
    if isinstance(d, str) and (len(d) < p.get("min_length", 0) or len(d) > p.get("max_length", len(d))):
        errs.append("default length is outside min_length/max_length")
    return errs


def check(schema, root=ROOT):
    errs = []
    for key in ["version", "phases", "stages", "output_file", "parameters"]:
        if key not in schema:
            errs.append(f"top level: missing {key}")
    if errs:
        return errs

    if [ph.get("id") for ph in schema["phases"]] != PHASES:
        errs.append(f"phases must be, in order: {', '.join(PHASES)}")

    stages = {}
    for stage, folder in schema["stages"].items():
        path = root / folder.replace("{env}", "example")
        if not path.is_dir():
            errs.append(f"stage {stage}: {path.relative_to(root)} does not exist")
            continue
        stages[stage] = root_variables(path)

    seen, answered, form = set(), {s: set() for s in stages}, 0
    for p in schema["parameters"]:
        pid = p.get("id", "<no id>")
        where = f"parameter {pid}"
        for key in ["id", "phase", "type", "question"]:
            if key not in p:
                errs.append(f"{where}: missing {key}")
        if pid in seen:
            errs.append(f"{where}: duplicate id")
        seen.add(pid)
        if p.get("phase") not in ASKING_PHASES:
            errs.append(f"{where}: phase must be discover or configure")
        if p.get("type") not in TYPES:
            errs.append(f"{where}: unknown type {p.get('type')}")
            continue
        if p["type"] == "enum":
            for c in p.get("choices", []):
                if c.get("supported", True) is False and not c.get("reason"):
                    errs.append(f"{where}: unsupported choice {c.get('value')} needs a reason")
            if not p.get("choices"):
                errs.append(f"{where}: enum needs choices")
        for dep in p.get("when", {}):
            if dep not in seen:
                errs.append(f"{where}: when refers to {dep}, which is not an earlier parameter")
        if p.get("ask", "always") not in {"always", "advanced", "never"}:
            errs.append(f"{where}: ask must be always, advanced or never")
        if p.get("ask") == "never" and "source" not in p and "default" not in p:
            errs.append(f"{where}: never asked, so it needs a source or a default")
        form += 1 if p.get("form") else 0
        errs += [f"{where}: {e}" for e in check_default(p)]
        for t in p.get("tfvars", []):
            stage, path = t.get("stage"), t.get("path", "")
            if stage not in stages:
                errs.append(f"{where}: tfvars stage {stage} is not declared")
                continue
            var = path.split(".")[0]
            if var not in stages[stage]:
                errs.append(f"{where}: {var} is not a variable of the {stage} root")
            answered[stage].add(var)

    if form > FORM_LIMIT:
        errs.append(f"{form} parameters are on the Actions form; keep it to {FORM_LIMIT}")
    for stage, variables in stages.items():
        for var, has_default in sorted(variables.items()):
            if not has_default and var not in answered[stage]:
                errs.append(f"stage {stage}: required variable {var} is not answered by any parameter")
    return errs


def main():
    schema = json.loads((ROOT / "schema" / "parameters.json").read_text())
    errs = check(schema)
    for e in errs:
        print(f"::error::{e}")
    if not errs:
        print(f"schema OK: {len(schema['parameters'])} parameters")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
