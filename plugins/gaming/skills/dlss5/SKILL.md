---
description: "Apply, track, tune, and remove the community DLSS 5 Neural Rendering mod (OptiScaler forks) in a PC game on Windows. Action router: assess (on-disk eligibility and anti-cheat check), apply (snapshot, then install), remove (byte-exact uninstall from the manifest), status (drift against the manifest), tune (OptiScaler.ini guidance), refetch (fork, driver and runtime release watch). Use when: 'apply DLSS 5 to this game', 'is this game safe for the DLSS 5 mod', 'remove the DLSS 5 mod', 'check for new OptiScaler DLSSNR releases', or DLSS 5, DLSSNR, or OptiScaler is mentioned with a game folder."
argument-hint: "[assess|apply|remove|status|tune|refetch] [<game-dir>]"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Route a DLSS 5 mod request to one action over the plugin's `Invoke-Dlss5Mod.ps1` script. Run
`/gaming:setup` first.
