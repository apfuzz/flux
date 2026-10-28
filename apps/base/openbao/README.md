# openbao

upgrade ldap auth plugin

```bash
bao auth tune -plugin-version=v0.2.0 ldap/
bao plugin reload -mounts=auth/ldap/ -scope=global
```
