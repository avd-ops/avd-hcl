# Guardrails

Every change follows these. They are not optional.

1. **Automate, never at the expense of security.** Identities and federation over secrets,
   least privilege, and a written workaround where automation isn't safe.
2. **HCL first.** Terraform or Packer does it if it can. Scripts are thin bootstrap glue or a
   stopgap until HCL can take over. Ansible only by a decision record that says why HCL can't.
3. **Works from a browser.** Every step runs in Azure Cloud Shell, on an iPad included. No local
   installs, no portal click-paths.
4. **Nothing identifies a real environment.** No tenant, subscription, object or client IDs,
   domains, IP ranges, emails, secrets, or employer or customer names in the repo, commits, issues
   or pull requests. Real values go in git-ignored `terraform.tfvars`, `*.auto.tfvars.json` and
   `*.pkrvars.hcl`. Examples use `contoso` names and all-zero GUIDs.
5. **Secrets never go through chat** or into the repo, state or logs. The person runs the step
   that handles one; Terraform uses write-only attributes and ephemeral reads.
6. **PRs only, plan first, nothing applies without an explicit yes.** Applies run only after a
   named reviewer approves them.
7. **Least privilege with every right written down.** A right that isn't listed with its reason
   is a bug. Privileged roles are held through PIM for the step that needs them.
8. **Read-only before anything changes.** The readiness check runs with Reader and never writes.
9. **Credit everything reused** ([CREDITS.md](../CREDITS.md)). Code from a repository with no
   license is reference only: facts, never code. No Nerdio code, provider or paid tool in the kit.
10. **Never leave the meter running, never delete the last copy.** A sandbox run has a written
    cost estimate and the owner's go first, and is torn down after with evidence. Teardown keeps
    logs and evidence.
11. **American English** in docs, output and comments.
