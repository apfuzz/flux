# flux apps - base

[HelmReleases - Recommended settings](https://fluxcd.io/flux/components/helm/helmreleases/#recommended-settings)

```yaml
spec:
  interval: 15m
  timeout: 5m
  chart:
    spec:
      chart: headlamp
      version: ">= 0.1.0"
      sourceRef:
        kind: HelmRepository
        name: headlamp
  driftDetection:
    mode: warn
  install:
    strategy:
      name: RetryOnFailure
  upgrade:
    crds: CreateReplace
    strategy:
      name: RetryOnFailure
```
