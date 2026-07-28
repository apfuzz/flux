# forgejo-runner

create 40 character hex value

```bash
openssl rand -hex 20
```

pre-register runner (returns runner uuid)

```bash
read -s RUNNER_TOKEN
forgejo forgejo-cli actions register \
  --scope gangsterkitties \
  --name kubernetes \
  --secret ${RUNNER_TOKEN}
```

add token to vault then create externalsecret
