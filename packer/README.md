# Packer Build
======

## How to
- Place vault and consul binaries in some directory.
- Edit values in `vars.json.example`.
- Export your `GOOGLE_APPLICATION_CREDENTIALS` env.

Build gcp image with packer
```
 packer build -var-file=vars.json.example centos.json
```