# Semarchy Design CLI package

The pipeline installs the Semarchy Design CLI on every run from:

```
ci-cd/tools/semarchy-sem-design-2.0.1.tgz.zip
```

The `.zip` contains `semarchy-sem-design-2.0.1.tgz`. The install step unzips it
at run time and installs the `.tgz`. The package is kept zipped because plain
`.tgz` files have been removed from this folder on the developer machine.

**Version 2.0.1 is the agreed version.** It's set in `ci-cd/config/common.yml`:

```yaml
- name: SEM_DESIGN_PACKAGE
  value: 'ci-cd/tools/semarchy-sem-design-2.0.1.tgz.zip'
- name: SEM_DESIGN_VERSION
  value: '2.0.1'
```

After installing, the pipeline runs `sem-design --version` and stops if the
result isn't `SEM_DESIGN_VERSION`. A different CLI can't be used by accident.

The CLI isn't on the public npm registry, so the package is committed here.

| | |
|---|---|
| Package | `@semarchy/sem-design` 2.0.1 |
| File | `semarchy-sem-design-2.0.1.tgz.zip` (553,990 bytes), containing `semarchy-sem-design-2.0.1.tgz` (554,771 bytes) |
| SHA-256 (.tgz inside) | `07a16085e4dc95424791865c1805636d7131ed7c20b8c6d94c6c590d409bf538` |
| Node.js | 20.x (`NODE_VERSION` in `common.yml`) |

`SEM_DESIGN_PACKAGE` can point to either a `.tgz` or a `.zip` that contains one.

## What 2.0.1 means for the pipeline

- Commands: `sem-design data-product build --data-product-folder src` and
  `sem-design data-product deploy --data-product-folder src ...`.
  The 1.x commands (`dm model build`, `dm data-location deploy`) still exist but
  are deprecated.
- Instance URL: `https://<tenant-url>` with **no `/dm`** suffix
  (`SDP_INSTANCE_URL` in `config/dev.yml`, `test.yml`, `prod.yml`).
- Authentication: `--client-id` / `--client-secret` (OAuth2 client credentials),
  taken from each environment's variable group.
- Model format: the project must be a 2.x *data product*. It needs one
  `DataProductProfile` and `CertificationJob` / `DataProductPrivGrant` element
  types. Run `ci-cd/scripts/Convert-ToDataProduct.ps1` once to convert the 1.x
  project (see `ci-cd/README.md`, *Before the first run*).
- 2.0.1 can exit with code 0 when a command fails. `scripts/Invoke-SemDesign.ps1`
  therefore also requires the CLI's `Build successful` / `Deployment successful`
  message before it lets a step pass.

## Upgrading later

1. Put the new package (`.tgz`, or a `.zip` containing it) in this folder.
2. Update `SEM_DESIGN_PACKAGE` and `SEM_DESIGN_VERSION` in `config/common.yml`.
3. Commit. The next run builds with it and deploys to Dev first. Test and Prod
   only run after Dev succeeds.
