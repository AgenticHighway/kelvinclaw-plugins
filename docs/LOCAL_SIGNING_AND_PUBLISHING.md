# First-Party AWS Signing And Publishing

AgenticHighway first-party plugin releases should use AWS KMS-backed Ed25519
signing. The public release artifacts stay in this repo, while AWS resources are
managed from the private `REDACTED_INTERNAL_REPO` repo.

The preferred release path is the GitHub Actions workflow in this repo:

- `.github/workflows/publish-first-party-package.yml`

That workflow uses GitHub OIDC plus the AWS role
`arn:aws:iam::REDACTED_ACCOUNT_ID:role/REDACTED_ROLE_NAME` on a Blacksmith
runner. The local CLI flow below remains the manual fallback and the path used
for ad hoc recovery.

## Rules

1. Keep private keys off-repo.
2. Commit only public keys in `trusted_publishers.kelvin.json`.
3. Never replace an old publisher id when the old signed artifacts are still
   published. Add a new publisher id instead.
4. For AgenticHighway-owned releases, prefer KMS-generated signing keys over
   ad-hoc local PEM files.

## First-Party Prerequisites

1. `REDACTED_INTERNAL_REPO` has already created the KMS signing key alias:
   - `REDACTED_KMS_ALIAS`
2. Your shell is using the expected AWS profile:

```bash
export AWS_PROFILE=REDACTED_AWS_PROFILE
```

3. You have a local clone of `agentichighway/kelvinclaw` for the signing helper
   scripts.

## Export The Publisher Public Key

Use the KelvinClaw helper script to export the first-party public key and stage a
trust-policy snippet:

```bash
/path/to/kelvinclaw/scripts/kms-ed25519-public-key.sh \
  --kms-key-id REDACTED_KMS_ALIAS \
  --kms-region us-east-1 \
  --format trust-policy \
  --publisher-id kelvin_firstparty_aws_v1 \
  --output /tmp/kelvin_firstparty_aws_v1.trust.json
```

Merge that public key into `trusted_publishers.kelvin.json` before publishing a
new first-party publisher id.

## Sign A Plugin Manifest

Use the main KelvinClaw repo script:

```bash
/path/to/kelvinclaw/scripts/plugin-sign.sh \
  --manifest /tmp/plugin-staging/plugin.json \
  --kms-key-id REDACTED_KMS_ALIAS \
  --kms-region us-east-1 \
  --publisher-id kelvin_firstparty_aws_v1 \
  --trust-policy-out /tmp/kelvin_firstparty_aws_v1.trust.json
```

This writes:

- `plugin.sig`
- a trust-policy snippet containing the KMS-derived public key

## Build A Release Tarball

Required package contents:

```text
plugin.json
plugin.sig
payload/
  <entrypoint>.wasm
```

Create the tarball:

```bash
tar -czf your.plugin.id-1.0.0.tar.gz -C /tmp/plugin-staging plugin.json payload plugin.sig
shasum -a 256 your.plugin.id-1.0.0.tar.gz
```

## Publish To This Repo

1. Add the tarball under `packages/<plugin_id>/<version>/`.
2. Append the new publisher public key to `trusted_publishers.kelvin.json` if
   this is a new publisher id.
3. Add or update the `index.json` entry with:
   - `id`
   - `version`
   - `package_url`
   - `sha256`
   - recommended: `trust_policy_url`, `quality_tier`, `tags`

## Validate

Offline repository validation:

```bash
scripts/validate-repository.sh
```

From a local KelvinClaw clone:

```bash
scripts/plugin-index-install.sh --index-url <index-url> --plugin <plugin-id>
scripts/plugin-list.sh --json
```

For current hosted first-party packages, prefer validating against a temporary
local index that points at the working-tree tarballs before opening a PR.

## Community Publisher Compatibility

Community publishers who are not using AgenticHighway-managed AWS KMS can still
use the PEM-based flow in the main KelvinClaw repo:

```bash
/path/to/kelvinclaw/scripts/plugin-sign.sh \
  --manifest /tmp/plugin-staging/plugin.json \
  --private-key /path/to/private.pem \
  --publisher-id your_publisher_id \
  --trust-policy-out /tmp/your-publisher.trust.json
```
