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

## Flux Operator

The Flux Operator is the best way to get started with Flux. It comes with the FluxInstance CRD, which is used to bootstrap a cluster.

There is a 1:1 relationship with the Flux Operator and FluxInstance resource. That is, a single operator deployed in a cluster manages a single FluxInstance resource, which in turn manages all other resources via controllers in that cluster.

### Install External Secrets Operator

A secret is needed for authentication to the git repo. There are lots of other secrets required by this codebase as well so might as well install External Secrets Operator now so the secrets can be synched from Vault as needed. More about this in [external-secrets-operator](scripts/external-secrets-operator/README.md).

It's a chicken/egg problem when building the cluster for the first time since there are no secrets to synchronize. In that case, the Kubernetes secrets can just be created from literal as needed until Vault is up and running.

```bash
./scripts/external-secrets-operator/eso.sh poptart vault.gangsterkitties.com
```

### Deploy Flux Operator

We could install a specific version with `--version` but in general we want the latest available.

```bash
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace && \
kubectl wait -n flux-system deploy/flux-operator --for=condition=Available --timeout=120s
```

### Apply external secret with git credentials

```bash
kubectl apply -f apps/base/flux/flux-gitlab.yaml -n flux-system && \
kubectl wait -n flux-system externalsecret/fluxcd-gitlab --for=condition=Ready
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
    version: "2.8.x"
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
    pullSecret: fluxcd-gitlab
    ref: refs/heads/main
    url: ssh://git@gitlab.com/gangsterkitties/flux
EOF
kubectl wait -n flux-system fluxinstance/flux --for=condition=Ready --timeout=120s
```
