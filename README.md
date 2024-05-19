# flux

Prerequisites

1. Create Git repo
2. Create SSH key pair
3. Add public key to Git repo
4. Clone repo
5. Install flux cli

Bootstrap Flux

```sh
GIT_URL=ssh://git@gitlab.com/gangsterkitties/flux
GIT_BRANCH=main
SSH_KEY_FILE=/home/aaron/.ssh/flux
K8S_CLUSTER=talos

flux bootstrap git \
  --url=$GIT_URL \
  --branch=$GIT_BRANCH \
  --private-key-file=$SSH_KEY_FILE \
  --path=clusters/$K8S_CLUSTER
```

Add bitnami helm repository

```sh
flux create source helm bitnami \
  --url=https://charts.bitnami.com/bitnami \
  --export > clusters/$K8S_CLUSTER/bitnami-source.yaml
```

Deploy redis helm chart with values from file

```sh
flux create helmrelease redis \
  --source=HelmRepository/bitnami.flux-system \
  --chart=redis \
  --chart-version=19.3.2 \
  --namespace=default \
  --values=helm/$K8S_CLUSTER/redis-values.yaml \
  --export > apps/$K8S_CLUSTERs/redis.yaml
  ```

Update chart version or values for redis

```sh
/bin/rm -f apps/$K8S_CLUSTERs/redis.yaml && \
flux create helmrelease redis \
  --source=HelmRepository/bitnami.flux-system \
  --chart=redis \
  --chart-version=19.3.2 \
  --namespace=default \
  --values=helm/$K8S_CLUSTER/redis-values.yaml \
  --export > apps/$K8S_CLUSTERs/redis.yaml
  ```

Add headlamp helm repository

```sh
flux create source helm headlamp \
  --url=https://headlamp-k8s.github.io/headlamp \
  --export > apps/$K8S_CLUSTER/headlamp.yaml
```

Create helm release for headlamp with values from file

```sh
flux create helmrelease headlamp \
  --source=HelmRepository/headlamp.flux-system \
  --chart=headlamp \
  --chart-version=0.20.0 \
  --namespace=kube-system \
  --values=helm/$K8S_CLUSTER/headlamp-values.yaml \
  --export >> apps/$K8S_CLUSTER/headlamp.yaml
  ```

Create kustomization for headlamp

```sh
mkdir manifests/$K8S_CLUSTER/headlamp
cp ../argocd/manifests/headlamp/ingress.yaml manifests/$K8S_CLUSTER/headlamp/

flux create kustomization headlamp \
  --source=GitRepository/flux-system \
  --path="./manifests/$K8S_CLUSTER/headlamp" \
  --prune=true \
  --interval=1h0m0s \
  --wait=true \
  --export >> apps/$K8S_CLUSTER/headlamp.yaml
```
