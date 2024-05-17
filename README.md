# flux

Prerequisites

1. Create Git repo
2. Create SSH key pair
3. Add public key to Git repo

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

Add podinfo repository to Flux

```sh
K8S_CLUSTER=talos
flux create source git podinfo \
  --url=https://github.com/stefanprodan/podinfo \
  --branch=master \
  --interval=1m \
  --export > ./clusters/$K8S_CLUSTER/podinfo-source.yaml
```
