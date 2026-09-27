# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GitOps monorepo (Flux CD) for a home lab: two Kubernetes clusters, `poptart` and `fivealive`. Flux syncs `clusters/<name>` from `main` and reconciles everything else from there. Layout follows the [Flux monorepo structure](https://fluxcd.io/flux/guides/repository-structure/#monorepo).

```
clusters/<name>        Flux sync target: ArtifactGenerator + Kustomizations
infrastructure/base    cluster-agnostic infra, split into infra-stage1..3
infrastructure/<name>  per-cluster overlays of infra-stageN
apps/base              cluster-agnostic HelmReleases/apps
apps/<name>            per-cluster overlays
scripts                bootstrap + validation helpers
```

For anything a human also needs to read — the artifact flattening rules and the overlay file conventions — the root `README.md` is the source of truth. This file records only what changes how you edit the repo.

## Validation

Two scripts, together the gate before merging to `main` (no test suite, lint config, or CI workflow in this repo):

```bash
./scripts/validate.sh               # manifests, overlays, Helm charts
./scripts/check-manifest-wiring.sh  # manifests that are never wired up
```

`validate.sh` is **vendored from upstream** ([fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example/blob/main/scripts/validate.sh)) — keep it unmodified so it can be updated cleanly, and put repo-specific checks in their own script the way `check-manifest-wiring.sh` does.

It needs the `flux schema` plugin (`flux plugin install schema`) plus `kustomize` or `kubectl` — it falls back to `kubectl kustomize`, so a standalone `kustomize` is optional. `helm` is only needed with `-H`. With no `.fluxschema.yml` present it runs on built-in defaults, validating against the ecosystem catalog at `schemas.fluxoperator.dev`. Useful flags: `-d <dir>` to scope a run, `-e <dir>` to exclude, `-b <file>` to dump every manifest and rendered overlay into one bundle with provenance comments, `-- <flags>` to override the defaults.

Three passes: standalone `*.yaml` outside kustomize/chart directories, each `kustomization.yaml` built with `--load-restrictor=LoadRestrictionsNone`, and Helm charts with `-H`. Currently 359 resources valid, 4 skipped, exit 0 — this does validate the CRDs, so ExternalSecrets, CloudNativePG, Gateway API, Cilium, and cert-manager get real schema checking. The only uncovered kinds are `k8s.keycloak.org/v2beta1 Keycloak` and `talos.dev/v1alpha1 ServiceAccount`: the ecosystem catalog has no schema for either, so `--skip-missing-schemas` passes them silently. That gap is accepted; closing it would take a `.fluxschema.yml` pinning an extra `--schema-location` for those two.

`check-manifest-wiring.sh` covers a gap `validate.sh` structurally cannot. A `*.yaml` inside a kustomize directory that no `kustomization.yaml` lists is skipped by the standalone pass *and* never emitted by any build, so it is neither validated nor deployed. The guard makes that an error, and reports files mentioned only in a comment as parked — the repo's convention for a deliberately disabled manifest, as in `apps/base/kps/recording-rules.yaml`. Matching is a filename heuristic, not a parse of the kustomization.

Still silent after both: a patch file listed under `resources:` (see `README.md`) — it builds cleanly and stays schema-valid while colliding with the base resource.

## Constraints when editing

`ArtifactGenerator` flattens `*/base/**` and `*/<cluster>/**` into one artifact, so at reconcile time the layout is `base/` next to `<cluster>/`. See "How manifests reach the cluster" in `README.md` for the full picture. The rules that follow from it:

- Overlays reference base with `../base/<app>` and cluster-only dirs with `./<app>`. Never reference across the repo root.
- `clusters/<name>/` is the only synced path; keep base trees out of it.
- Adding an app or infra component means three edits: new directory under `base/`, add it to the `copy` list in `clusters/<name>/artifacts.yaml`, wire it into the overlay `kustomization.yaml`.
- A loose `<app>.yaml` at an overlay root is a `patches:` entry, never a `resources:` entry; a subdirectory is the reverse. A resource dir named as a `patches:` path fails the build, but a patch file listed under `resources:` builds cleanly and applies a partial object that collides with the base resource — `validate.sh` will not flag that, so check it yourself.

## Staged infrastructure

`infra-stage1` (CRDs/operators/storage) → `infra-stage2` (instances needing those) → `infra-stage3` (networking/ingress/external-dns, which need workloads to route to). Chained with `dependsOn` in `clusters/<name>/infrastructure.yaml`; `apps.yaml` depends on `infra-stage3`. Rationale is in `infrastructure/base/README.md` — put a new component in the earliest stage whose dependencies already exist.

## Conventions

- YAML: 2-space indent, LF, final newline, no trailing whitespace (`.editorconfig`).
- HelmRelease settings follow the pattern documented in `apps/base/README.md` (interval 15m, timeout 5m, `driftDetection.mode: warn`, `RetryOnFailure` install/upgrade strategies, `crds: CreateReplace`).
- Secrets are never committed in plaintext. They come from Vault via External Secrets Operator: `ClusterSecretStore` named `vault-backend` (per-cluster under `apps/<name>/external-secrets/css.yaml`) with a per-cluster Kubernetes auth mount (`eso-poptart`, etc.).

## Bootstrap

Per-cluster and one-time; the full sequence with commands is in `README.md`. Order matters: install External Secrets Operator (`./scripts/external-secrets-operator/eso.sh <cluster> <vault-address>`) → `HelmRelease flux-operator` → apply `apps/base/flux/flux-forgejo.yaml` and wait for the ExternalSecret → apply a `FluxInstance` pointing at `clusters/<cluster>`. On a brand-new cluster before Vault exists, create the required Secrets from literals by hand (the chicken-and-egg case noted in the README). Once bootstrapped, the `FluxInstance` in the repo manages the cluster and its `sync.path` is set by the overlay JSON patch.
