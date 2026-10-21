# Parameter schema

Adapted from nerdio-hcl's `schema/README.md` (Apache-2.0, commit `75f59bc`); see
[CREDITS.md](../CREDITS.md). Changes: AVD-native parameters and stages, and the fields this kit
doesn't use yet are left out.

`parameters.json` is the one list of deployment parameters. The setup chat, the command line and
the GitHub Actions form all read it (they come in later phases), and each parameter maps onto a
Terraform variable in a stage. Change a question, default or rule here, never in one front door.

## A parameter

```json
{
  "id": "vm_size",
  "phase": "configure",
  "type": "string",
  "pattern": "^Standard_[A-Za-z0-9_]+$",
  "question": "Session host VM size?",
  "help": "Memory-optimized E-series suits multi-session hosts.",
  "default": "Standard_E4as_v5",
  "tfvars": [{ "stage": "platform", "path": "vm_size" }]
}
```

| Field | Meaning |
|---|---|
| `id` | Answer key, command-line name and form input name |
| `phase` | `discover` or `configure` (the phases that ask questions) |
| `type` | `string`, `int`, `bool`, `enum`, `uuid`, `cidr`, `string_list`, `ipv4_list`, `group_list` (names or IDs, looked up in Entra) |
| `question`, `help` | What every front door shows. Plain language; `help` says why it matters |
| `choices` | For `enum`: `value`, `label`, and `supported: false` plus `reason` for options the kit can't build yet |
| `pattern`, `min_length`, `max_length`, `min`, `max`, `min_prefix`, `max_prefix`, `min_items` | Validation, kept in step with the Terraform variable's own validation |
| `default` | A value, or a template such as `"avd-{environment}"` that uses earlier answers |
| `when` | Only asked when earlier answers match, e.g. `{"create_nat_gateway": [false]}` |
| `ask` | `always` (default), `advanced` (only when asked for), or `never` (read from the account) |
| `source` | `tenant` or `subscription`: read from `ARM_*` or `az account show`, never asked or saved |
| `tfvars` | Where the value lands: `stage`, a dotted `path` whose first part is a variable of that stage's root, and optional `render` (`list`) or `omit_empty` |
| `form` | Show it on the Actions form. Keep the form to 10 inputs |
| `checks` | Cross-field checks, such as `subnets_in_address_space` |
| `sources` | External docs the chat cites |

Top level: `phases` (all eight), `stages` (folder per stage), `output_file` and `constants`.

## Checks

`python3 scripts/schema/check.py` runs in CI. It checks the schema's shape, that every `tfvars`
path starts with a variable declared in that stage's root, that every required variable of a root
is answered, and that defaults pass their own rules. Tests:
`python3 -m unittest discover -s scripts/schema`.
