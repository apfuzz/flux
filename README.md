# Flux CD

This repository contains Flux CD resources that automate the deployment and configuration of nearly everything in my home lab Kubernetes cluster. It is based on the monorepo structure as described on [fluxcd.io](https://fluxcd.io/flux/guides/repository-structure/#monorepo) and looks something like this:

```sh
├── apps                  depends on infrastructure, no interdependencies
│   ├── base
│   ├── fivealive
│   └── poptart
├── clusters              flux sync path
│   ├── fivealive
│   └── poptart
├── infrastructure        crds, networking with interdependencies
│   ├── base
│   │   ├── infra-stage1
│   │   ├── infra-stage2
│   │   ├── infra-stage3
│   ├── fivealive
│   │   ├── infra-stage1
│   │   ├── infra-stage2
│   │   ├── infra-stage3
│   └── poptart
│       ├── infra-stage1
│       ├── infra-stage2
│       └── infra-stage3
└── scripts               various utility scripts
```

## How manifests reach the cluster

`clusters/<name>` is the only path Flux syncs directly. Everything else is flattened into two `ExternalArtifact`s by the `ArtifactGenerator` in `clusters/<name>/artifacts.yaml`:

- `apps` ← `apps/base/**` + `apps/<name>/**`
- `infrastructure` ← `infrastructure/base/**` + `infrastructure/<name>/**`

Inside an artifact the layout is `base/` and `<name>/` side by side. That is why overlays reference base directories as `../base/<app>` and cluster-only directories as `./<app>`, and why nothing may reference across the repo root. It also means `clusters/<name>/` must contain only the sync target — never a base tree.

Adding an app or infrastructure component takes three edits: create the directory under `base/`, add it to the `copy` list in `clusters/<name>/artifacts.yaml`, and wire it into the overlay's `kustomization.yaml`.

### Overlay files

A per-cluster overlay (`apps/<name>`, `infrastructure/<name>/infra-stageN`) is a `kustomization.yaml` with `resources:` and `patches:`. Two kinds of local files live alongside it:

- **Patch files** — a loose `<app>.yaml` at the overlay root (e.g. `apps/poptart/flux.yaml`,
  `infrastructure/poptart/infra-stage1/cert-manager.yaml`). These hold only the overriding spec and are
  referenced from `patches:` with `path:` and `target:`. They are *not* resources.
- **Resource directories** — subdirectories with their own `kustomization.yaml` holding manifests only that
  cluster needs (e.g. `apps/fivealive/talos-etcd/`, `infrastructure/poptart/infra-stage3/keycloak/`). These
  are referenced from `resources:`.

Referencing one where the other belongs is a real bug, and the two directions fail differently. Pointing `patches:` at a resource directory fails the build (`must resolve to a file`), so `validate.sh` catches it. Listing a patch file under `resources:` builds cleanly and emits the partial manifest as an object of its own, which then collides with the full resource defined in `base/` — nothing fails, so this one has to be caught in review.

Inline JSON patches in `patches:` cover fields with no natural patch file: `/spec/sync/path` on the `FluxInstance` selects `clusters/<name>`, and `/spec/username` on the Slack `Provider` names the cluster in alerts.

## Flux Operator

The Flux Operator is the best way to get started with Flux. It comes with the FluxInstance CRD, which is used to bootstrap a cluster.

There is a 1:1 relationship with the Flux Operator and FluxInstance resource. That is, a single operator deployed in a cluster manages a single FluxInstance resource, which in turn manages all other resources via controllers in that cluster.

### Install External Secrets Operator

A secret is needed for authentication to the git repo. There are lots of other secrets required by this codebase as well so might as well install External Secrets Operator now so the secrets can be synched from Vault as needed. More about this in [external-secrets-operator](scripts/external-secrets-operator/README.md).

```bash
./scripts/external-secrets-operator/eso.sh poptart vault.gangsterkitties.com
```

It's a chicken/egg problem when building the cluster for the first time since there are no secrets to synchronize. In that case, the Kubernetes secrets can just be created from literal as needed until Vault is up and running.

### Deploy Flux Operator

A specific version can be installed by using `--version` but the latest available is generally preferred.

```bash
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --wait
```

### Apply external secret with git credentials

```bash
kubectl apply -f apps/base/flux/flux-forgejo.yaml -n flux-system && \
kubectl wait -n flux-system externalsecret/flux-forgejo --for=condition=Ready
```

### Create FluxInstance resoruce (aka "bootstrap" cluster)

This will install Flux components and sync with the git repo then Flux will deploy everything else.

```sh
K8S_CLUSTER=poptart
cat <<EOF | kubectl apply -f -
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution:
    version: "2.9.x"
    registry: "ghcr.io/fluxcd"
    artifact: "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests"
  components:
    - source-controller
    - source-watcher
    - kustomize-controller
    - helm-controller
    - notification-controller
  cluster:
    type: kubernetes
    size: small
  sync:
    kind: GitRepository
    path: clusters/$K8S_CLUSTER
    pullSecret: flux-forgejo
    ref: refs/heads/main
    url: ssh://git@git.gangsterkitties.com:1022/gangsterkitties/flux.git
EOF
kubectl wait -n flux-system fluxinstance/flux --for=condition=Ready --timeout=120s
```
