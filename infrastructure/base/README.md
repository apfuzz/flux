# flux infrastructure - base

Cluster-agnostic infrastructure, split into three stages that are applied in order. The staging is a dependency ordering, not a categorization: each stage needs something the previous one installed.

1. **infra-stage1** — CRDs, operators, and storage. Must exist before anything can consume it (cert-manager, CloudNativePG, gateway-api CRDs, kube-prometheus-stack CRDs, Longhorn, RBAC).
2. **infra-stage2** — instances that depend on those operators (cert-manager issuers and wildcard certificates, Postgres clusters, monitoring storage).
3. **infra-stage3** — networking and ingress (Cilium, Traefik, external-dns). These route to workloads, so they come last.

`clusters/<name>/infrastructure.yaml` chains the three with `dependsOn`, and `clusters/<name>/apps.yaml` depends on `infra-stage3`. Put a new component in the earliest stage whose dependencies already exist — promoting it later means moving the directory and its overlay entries.
