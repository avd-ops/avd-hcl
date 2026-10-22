#!/usr/bin/env python3
"""Ask the schema's questions, and turn the answers into each stage's tfvars.

    answers.py init [--advanced] [--file .avd/answers.json]
        Ask the questions in schema/parameters.json on the command line and save the answers.
        Only what you typed or picked is saved; defaults stay in the schema.
    answers.py render [--file .avd/answers.json] [--env-dir environments/example]
        Check the answers against the schema and write <stage>/setup.auto.tfvars.json for every
        stage. The deploy workflow runs this before each plan.

The setup chat and the Actions form read the same schema (schema/README.md), so a question,
default or rule changes there, never here. Tenant and subscription are never asked or saved:
render reads them from ARM_TENANT_ID and ARM_SUBSCRIPTION_ID, or from `az account show`.
Group names are looked up in Entra with `az ad group show`; object IDs pass through.
Nothing here is a secret, and nothing secret is ever asked.
"""
import argparse
import ipaddress
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "schema" / "parameters.json"
DEFAULT_ANSWERS = ROOT / ".avd" / "answers.json"
UUID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
LIST_TYPES = {"string_list", "ipv4_list", "group_list"}


class AnswerError(ValueError):
    pass


def az(*args):
    out = subprocess.run(["az", *args, "-o", "tsv"], capture_output=True, text=True)
    if out.returncode != 0:
        raise AnswerError(f"az {' '.join(args[:3])} failed: {out.stderr.strip().splitlines()[-1] if out.stderr.strip() else out.returncode}")
    return out.stdout.strip()


def account_source(kind):
    """Tenant or subscription from the pipeline's ARM_* variables, else the signed-in account."""
    env = {"tenant": "ARM_TENANT_ID", "subscription": "ARM_SUBSCRIPTION_ID"}[kind]
    if os.environ.get(env):
        return os.environ[env]
    return az("account", "show", "--query", {"tenant": "tenantId", "subscription": "id"}[kind])


def lookup_group(name):
    """An Entra group's object ID from its display name. Exactly one match, or an error."""
    found = az("ad", "group", "list", "--filter", f"displayName eq '{name.replace(chr(39), chr(39) * 2)}'", "--query", "[].id")
    ids = [line for line in found.splitlines() if line]
    if len(ids) != 1:
        raise AnswerError(f"group '{name}': expected one Entra group with that name, found {len(ids)}")
    return ids[0]


def applies(p, values):
    """A parameter with `when` only counts when the earlier answers match."""
    return all(values.get(dep) in allowed for dep, allowed in p.get("when", {}).items())


def expand(default, values):
    """A default such as "avd-{environment}" uses earlier answers."""
    if isinstance(default, str):
        return re.sub(r"\{([a-z_]+)\}", lambda m: str(values.get(m.group(1), m.group(0))), default)
    return default


def coerce(p, raw):
    """Turn typed text (or a JSON value) into the parameter's type."""
    t = p["type"]
    if not isinstance(raw, str):
        return raw
    text = raw.strip()
    if t == "int":
        try:
            return int(text)
        except ValueError:
            raise AnswerError(f"{p['id']}: '{text}' is not a whole number")
    if t == "bool":
        if text.lower() in {"y", "yes", "true", "1"}:
            return True
        if text.lower() in {"n", "no", "false", "0"}:
            return False
        raise AnswerError(f"{p['id']}: answer yes or no")
    if t in LIST_TYPES:
        return [s.strip() for s in text.split(",") if s.strip()]
    return text or None


def validate(p, v):
    """Problems with one value against the parameter's own rules. Empty means valid."""
    pid, t = p["id"], p["type"]
    if v is None:
        return []
    errs = []
    if t == "int" and (not isinstance(v, int) or isinstance(v, bool)):
        return [f"{pid}: must be a whole number"]
    if t == "bool" and not isinstance(v, bool):
        return [f"{pid}: must be true or false"]
    if t in LIST_TYPES:
        if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
            return [f"{pid}: must be a list of text values"]
        if len(v) < p.get("min_items", 0):
            errs.append(f"{pid}: needs at least {p['min_items']}")
        if t == "ipv4_list":
            for x in v:
                try:
                    ipaddress.IPv4Address(x)
                except ValueError:
                    errs.append(f"{pid}: {x} is not an IPv4 address")
        return errs
    if t in {"string", "enum", "uuid", "cidr"} and not isinstance(v, str):
        return [f"{pid}: must be text"]
    if t == "int" and (("min" in p and v < p["min"]) or ("max" in p and v > p["max"])):
        errs.append(f"{pid}: must be from {p.get('min')} to {p.get('max')}")
    if t == "enum":
        choice = next((c for c in p.get("choices", []) if c["value"] == v), None)
        if choice is None:
            errs.append(f"{pid}: pick one of {', '.join(c['value'] for c in p['choices'])}")
        elif choice.get("supported", True) is False:
            errs.append(f"{pid}: {v} isn't built yet: {choice['reason']}")
    if t == "uuid" and not UUID.match(v):
        errs.append(f"{pid}: must be a GUID")
    if t == "cidr":
        try:
            net = ipaddress.ip_network(v)
        except ValueError:
            return [f"{pid}: {v} is not a CIDR block such as 10.50.0.0/20"]
        if ("min_prefix" in p and net.prefixlen < p["min_prefix"]) or ("max_prefix" in p and net.prefixlen > p["max_prefix"]):
            errs.append(f"{pid}: prefix length must be from /{p.get('min_prefix')} to /{p.get('max_prefix')}")
    if isinstance(v, str):
        if "pattern" in p and not re.fullmatch(p["pattern"], v):
            errs.append(f"{pid}: '{v}' doesn't match {p['pattern']}")
        if len(v) < p.get("min_length", 0) or len(v) > p.get("max_length", len(v)):
            errs.append(f"{pid}: must be {p.get('min_length', 0)} to {p['max_length']} characters")
    return errs


def cross_checks(schema, values):
    errs = []
    for p in schema["parameters"]:
        if "subnets_in_address_space" in p.get("checks", []) and values.get(p["id"]):
            space = ipaddress.ip_network(values[p["id"]])
            subnets = [q for q in schema["parameters"] if q["type"] == "cidr" and q["id"] != p["id"] and values.get(q["id"])]
            nets = {q["id"]: ipaddress.ip_network(values[q["id"]]) for q in subnets}
            for qid, net in nets.items():
                if not net.subnet_of(space):
                    errs.append(f"{qid}: {net} is outside {p['id']} {space}")
            ids = sorted(nets)
            for i, a in enumerate(ids):
                for b in ids[i + 1:]:
                    if nets[a].overlaps(nets[b]):
                        errs.append(f"{a} and {b} overlap")
    return errs


def resolve(schema, answers, source=account_source, group=lookup_group):
    """Every parameter's final value, in schema order. Raises AnswerError listing every problem."""
    known = {p["id"] for p in schema["parameters"]}
    errs = [f"{k}: not a parameter in schema/parameters.json" for k in answers if k not in known]
    values = {}
    for p in schema["parameters"]:
        pid = p["id"]
        if not applies(p, values):
            continue
        if "source" in p:
            if pid in answers:
                errs.append(f"{pid}: read from the signed-in account, never saved in answers")
            try:
                values[pid] = source(p["source"])
            except AnswerError as e:
                errs.append(f"{pid}: {e}")
            continue
        try:
            v = coerce(p, answers[pid]) if pid in answers else expand(p.get("default"), values)
        except AnswerError as e:
            errs.append(str(e))
            continue
        if v is None and "default" not in p:
            errs.append(f"{pid}: needs an answer ({p['question']})")
            continue
        problems = validate(p, v)
        errs += problems
        if p["type"] == "group_list" and not problems:
            try:
                v = [x if UUID.match(x) else group(x) for x in v]
            except AnswerError as e:
                errs.append(f"{pid}: {e}")
        values[pid] = v
    errs += cross_checks(schema, values)
    if errs:
        raise AnswerError("\n".join(errs))
    return values


def tfvars(schema, values):
    """{stage: {variable: value}} from the resolved values."""
    out = {stage: {} for stage in schema["stages"]}
    for p in schema["parameters"]:
        if p["id"] not in values:
            continue
        for t in p.get("tfvars", []):
            v = values[p["id"]]
            if t.get("omit_empty") and v in (None, "", []):
                continue
            if t.get("render") == "list":
                v = [v]
            node = out[t["stage"]]
            *parents, leaf = t["path"].split(".")
            for part in parents:
                node = node.setdefault(part, {})
            node[leaf] = v
    return out


def stage_dirs(schema, env_dir):
    """Each stage's root under the chosen environments folder."""
    return {stage: env_dir / Path(folder).name for stage, folder in schema["stages"].items()}


def render(schema, answers, env_dir, **lookups):
    values = resolve(schema, answers, **lookups)
    written = []
    for stage, data in tfvars(schema, values).items():
        path = stage_dirs(schema, env_dir)[stage] / schema["output_file"]
        path.write_text(json.dumps(data, indent=2) + "\n")
        written.append(path)
    return written


def ask(p, values, prompt=input, say=print):
    """One question on the command line; returns the typed answer or None to keep the default."""
    default = expand(p.get("default"), values)
    say(f"\n{p['question']}")
    if p.get("help"):
        say(f"  {p['help']}")
    choices = [c for c in p.get("choices", []) if c.get("supported", True)]
    for i, c in enumerate(choices, 1):
        say(f"  {i}. {c['label']}")
    shown = ", ".join(default) if isinstance(default, list) else default
    while True:
        raw = prompt(f"  [{'' if shown is None else shown}] > ").strip()
        if not raw:
            if default is None and "default" not in p:
                say("  This one needs an answer.")
                continue
            return None
        if choices and raw.isdigit() and 1 <= int(raw) <= len(choices):
            raw = choices[int(raw) - 1]["value"]
        try:
            v = coerce(p, raw)
        except AnswerError as e:
            say(f"  {e}")
            continue
        problems = validate(p, v)
        if problems:
            say("  " + "; ".join(problems))
            continue
        return v


def init(schema, advanced=False, previous=None, prompt=input, say=print):
    answers, values = dict(previous or {}), {}
    for p in schema["parameters"]:
        if "source" in p or p.get("ask") == "never" or not applies(p, values):
            continue
        if p.get("ask") == "advanced" and not advanced:
            values[p["id"]] = answers.get(p["id"], expand(p.get("default"), values))
            continue
        v = ask(p, values, prompt, say)
        if v is not None:
            answers[p["id"]] = v
        values[p["id"]] = answers.get(p["id"], expand(p.get("default"), values))
    return answers


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("init", help="ask the questions and save the answers")
    i.add_argument("--advanced", action="store_true", help="also ask the advanced questions")
    i.add_argument("--file", type=Path, default=DEFAULT_ANSWERS)
    r = sub.add_parser("render", help="write each stage's setup.auto.tfvars.json")
    r.add_argument("--file", type=Path, default=DEFAULT_ANSWERS)
    r.add_argument("--env-dir", type=Path, default=ROOT / "environments" / "example")
    args = ap.parse_args(argv)
    schema = json.loads(SCHEMA.read_text())

    if args.cmd == "init":
        previous = json.loads(args.file.read_text()) if args.file.exists() else {}
        answers = init(schema, args.advanced, previous)
        args.file.parent.mkdir(parents=True, exist_ok=True)
        args.file.write_text(json.dumps(answers, indent=2) + "\n")
        print(f"\nSaved {len(answers)} answers to {args.file}. Next: {Path(sys.argv[0]).name} render")
        return 0

    if not args.file.exists():
        print(f"No answers at {args.file}. Run init first.", file=sys.stderr)
        return 2
    try:
        written = render(schema, json.loads(args.file.read_text()), args.env_dir)
    except AnswerError as e:
        for line in str(e).splitlines():
            print(f"x {line}", file=sys.stderr)
        return 1
    for path in written:
        print(f"Wrote {path.relative_to(ROOT) if path.is_relative_to(ROOT) else path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
