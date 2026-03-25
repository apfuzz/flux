# External Secrets Operator

External Secrets Operater (ESO) synchronizes secrets from a provider, such as HashiCorp Vault to a Kubernetes cluster. There are several steps required on the Kubernetes side and Vault side to get this working. The `eso.sh` script will do all of this, including creating a test secret to make sure everything is working.

## Reference

- [HashiCorp Vault - Kubernetes auth method](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [ESO provider - HashiCorp Vault](https://external-secrets.io/latest/provider/hashicorp-vault/)

## Deploy ESO

```sh
./eso.sh <K8s cluster name> <Vault address>
```
