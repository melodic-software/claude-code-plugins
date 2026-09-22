---
description: "Verify and provision the gaming plugin's DLSS 5 mod prerequisites on Windows. check (read-only): pwsh, NVIDIA GPU and driver, data directory, runtime DLL, provisioned fork builds, orphaned state. apply: create the data directory, seed the ledger, place the runtime DLL from a configured path, an installed DLSS 5 title, or the configured runtime source, and download the pinned fork build. Use when: 'set up the gaming plugin', 'set up DLSS 5', 'is my DLSS 5 setup ready', 'provision the DLSS 5 mod'. Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and provision the prerequisites for `/gaming:dlss5`. `check` is read-only; `apply`
provisions, then re-runs `check`.
