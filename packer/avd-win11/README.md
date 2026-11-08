# Windows 11 multi-session golden image

Packer builds a Windows 11 Enterprise multi-session + Microsoft 365 image (Gen2, Trusted Launch)
and publishes a versioned image to the Compute Gallery from `environments/example/02-images`
(`modules/image-gallery`). Pin the resulting version ID in `image_id` and roll it out to session
hosts by switching `host_generation` (`a` / `b`).

```bash
cd packer/avd-win11
cp example.pkrvars.hcl sandbox.pkrvars.hcl     # git-ignored; fill in from 02-images outputs
packer init .
packer build -var-file=sandbox.pkrvars.hcl .
```

Build steps: base settings (time zone redirection, Storage Sense off, disconnected session limit,
automatic OS and Office updates off), Windows Update, WDOT at a pinned commit with event-log and
registry verification, and sysprep.

## Windows Desktop Optimization Tool (WDOT)

[WDOT](https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool) is the
Virtual Desktop Team's successor to VDOT. The kit drives it from HCL:

- **Pinned source.** The build host fetches WDOT with `git` at the commit in `wdot_source`
  (git checks the content against the commit hash) and uploads it to the build VM, so the VM
  never downloads code from GitHub. The zip is cached in `packer_cache/`.
- **Event-log pre-creation and verification.** WDOT v1.1 passes `-Source` twice to `New-EventLog`
  and returns without an exit code when it skips work (avd-landing-zone lesson 0031). `03-wdot.ps1`
  creates the `WDOT` event log and its sources first, clears `HKLM:\SOFTWARE\WDOT` `LastRunTime`,
  and verifies after the run that `LastRunTime` was written and the `WDOT` event log recorded
  `WDOT Total Run Time*`.
- **Profiles in HCL** (`wdot.pkr.hcl`). WDOT ships every setting as `Skip`; a profile says which
  config files flip to `Apply` and which WDOT categories run. `DiskCleanup` is omitted so build
  logs and event logs are not wiped before verification.

| `wdot_profile` | What it applies |
|---|---|
| `avd-multisession` (default) | Local policy, default user, Edge, SMB client and autologger settings. No services, scheduled tasks or app removals. |
| `minimal` | SMB client tuning and autologgers. |
| `none` | Skips WDOT. |
