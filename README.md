# AVD Lab Kit

> **Status: pre-release (v1 in progress).** The scaffold, CI, and leak-prevention controls are in place; the Bicep modules and PowerShell orchestrator are being built. Targeting `v1.0.0`. Nothing here deploys yet.

A fully scripted, repeatable Azure Virtual Desktop lab — "AVD as code." Spin it up, demonstrate the pattern, tear it down cleanly in one command. Bicep modules handle everything that's a clean ARM resource; a thin PowerShell orchestrator wraps them for the things that aren't (Microsoft Graph calls, Azure AD Kerberos enablement, and step-by-step narration you can talk over during a live demo).

This is deliberately the **Easy Mode** build: Entra ID-joined session hosts, no domain controller, no on-prem dependency, one resource group. It's meant to be understood in one sitting and forked without standing up AD DS first. See [Easy Mode / Hard Mode](#easy-mode--hard-mode) for what that leaves out, and why saying so out loud is the point.

## Prerequisites / Getting started

**1. Confirm tooling.**

- PowerShell 7+
- Az PowerShell modules: `Az.Accounts`, `Az.Resources` (these deploy Bicep directly — no separate Azure CLI dependency)
- Bicep CLI (`az bicep install`) or the VS Code Bicep extension, for authoring and local linting
- Microsoft Graph PowerShell SDK: `Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, `Microsoft.Graph.Groups`

**2. Run the prerequisites check** against your target subscription and tenant:

```powershell
./scripts/Initialize-AvdLabPrerequisites.ps1
```

It registers the four required resource providers for you (idempotent, safe to re-run) and *reports* on everything it can't safely fix: vCPU quota, Windows 11 Enterprise multi-session licensing, Entra ID Security Defaults, MDM auto-enrollment scope, and whether your identity actually holds the roles the deployment needs.

**3. Resolve whatever it flags — manually.** Licensing procurement, a quota increase request, registering MFA on the account you'll demo with: none of these are things a script can do for you, and a quota increase is not instant. Do this early.

**4. Fill in your local override file.** Never edit the tracked parameter files, which hold placeholders only:

```powershell
Copy-Item bicep/parameters/avdlab.bicepparam bicep/parameters/avdlab.local.bicepparam
Copy-Item orchestrator.config.json orchestrator.local.config.json
```

Both `*.local.*` patterns are gitignored. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full secrets policy and the pre-commit hook setup.

## Deploying

```powershell
./scripts/Deploy-AvdLab.ps1 -Validate    # dry run: what-if against every module, touches nothing
./scripts/Deploy-AvdLab.ps1              # the real thing
```

The orchestrator deploys each module as its own discrete step — network, storage, host pool, workspace, app group, session hosts, monitoring, scaling plan — narrating as it goes, and stopping cleanly if any phase fails rather than pressing on into a broken deployment.

On success it writes an **as-built report** (Markdown + JSON) to `./reports/`: resource names and IDs, host pool and workspace connection info, the FSLogix share path, the scaling plan schedule, and how long the whole thing took. That document is the durable record of what's running — unlike terminal scrollback, which is gone the moment you close the window.

## Tearing down

```powershell
./scripts/Remove-AvdLab.ps1
```

Everything lives in one resource group, so teardown is a single `Remove-AzResourceGroup` under the hood.

## Troubleshooting

When something breaks, the orchestrator automatically bundles an evidence folder. You can also generate one on demand, against a live or partially-deployed environment:

```powershell
./scripts/New-AvdLabReport.ps1 -Mode Evidence -ResourceGroupName rg-avdlab-weuc
```

You get the full structured transcript, the Bicep deployment operation details for whichever step failed, and resource state at the point of failure — what happened, and exactly where it broke.

## Easy Mode / Hard Mode

**Easy Mode (v1 — this repo)** is the simplest deployable AVD lab that's still a legitimate, real-world-shaped pattern:

- Entra ID-joined session hosts — no AD DS, no Entra Domain Services
- Pooled host pool, Windows 11 Enterprise multi-session, 2–3 hosts with an autoscale scaling plan
- FSLogix profile containers on Azure Files, via Azure AD Kerberos
- Log Analytics workspace + AVD Insights
- Desktop app group, workspace, a single VNet, and a cost guardrail budget alert
- **Zero public IPs and zero inbound RDP rules.** That's not a shortcut taken for demo simplicity — AVD's reverse-connect transport means session hosts only ever make *outbound* HTTPS connections. Nothing ever connects inbound to a session host.

It runs happily in a subscription that already has other workloads. Isolation comes from a dedicated resource group, so it never touches anything outside it. An empty subscription is a convenience, never a requirement.

**Hard Mode (roadmap, not built here)** is what it looks like at an actual customer, layered onto the same module foundation: hybrid AD DS join, VNet peering to an existing hub, Private Link with custom DNS, custom golden images, and Intune management (v2). Then Bastion, App Attach, GPU hosts, multi-region DR (v3). Then Azure Local (v4). Azure Government / GCC High is a parallel variant rather than a layer — different endpoints, different image availability, its own compliance overlay (v5).

Easy Mode's brownfield story is *non-interference*. Hard Mode's is *integration* — peering into a corporate VNet, joining an existing forest, using existing DNS. That's the real distinction between the tiers, not "simple vs. complex."

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — particularly the secrets and leak-prevention norms, and the scope rule that keeps Easy Mode easy.

## License

[MIT](LICENSE)
