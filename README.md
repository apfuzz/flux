# Flux CD

This repository is dedicated to Flux CD.

It follows the monorepo design as described on [fluxcd.io](https://fluxcd.io/flux/guides/repository-structure/#monorepo).

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
├── scripts               various utility scripts
└── templates             flux resource templates
```

## Flux Operator

The Flux Operator is the best way to get started with Flux. It comes with the FluxInstance CRD, which is used to bootstrap a cluster.

There is a 1:1 relationship with the Flux Operator and FluxInstance resource. That is, a single operator deployed in a cluster manages a single FluxInstance resource, which in turn manages all other resources via controllers in that cluster.

### Deploy Flux Operator

```bash
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace && \
kubectl wait -n flux-system deploy/flux-operator --for=condition=Available --timeout=60s
```

### Apply external secret with git credentials

```bash
kubectl apply -f apps/base/flux/flux-gitlab.yaml -n flux-system && \
kubectl wait -n flux-system externalsecret/fluxcd-gitlab --for=condition=Ready --timeout=60s
```

### Create FluxInstance resoruce (aka "bootstrap" cluster)

```sh
cat <<EOF | kubectl apply -f -
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution:
    version: "2.7.x"
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
    path: clusters/poptart
    pullSecret: fluxcd-gitlab
    ref: refs/heads/main
    url: ssh://git@gitlab.com/gangsterkitties/flux
EOF
kubectl wait -n flux-system fluxinstance/flux --for=condition=Ready --timeout=60s
```
