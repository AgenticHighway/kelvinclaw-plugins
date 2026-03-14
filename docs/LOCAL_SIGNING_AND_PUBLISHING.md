# Local Signing And Publishing

This repository currently uses a manual local signing flow. No GitHub secrets,
external key service, or non-GitHub deployment infrastructure is required.

## Rules

1. Keep private keys off-repo.
2. Commit only public keys in `trusted_publishers.kelvin.json`.
3. Never replace an old publisher id when the old signed artifacts are still
   published. Add a new publisher id instead.

## Generate A Local Ed25519 Key

Example local key path:

```bash
mkdir -p ~/.kelvinclaw-signing
chmod 700 ~/.kelvinclaw-signing
openssl genpkey -algorithm Ed25519 \
  -out ~/.kelvinclaw-signing/kelvin_firstparty_v1_ed25519_private.pem
chmod 600 ~/.kelvinclaw-signing/kelvin_firstparty_v1_ed25519_private.pem
```

## Sign A Plugin Manifest

Use the main KelvinClaw repo script:

```bash
/path/to/kelvinclaw/scripts/plugin-sign.sh \
  --manifest /tmp/plugin-staging/plugin.json \
  --private-key ~/.kelvinclaw-signing/kelvin_firstparty_v1_ed25519_private.pem \
  --publisher-id kelvin_firstparty_v1 \
  --trust-policy-out /tmp/kelvin_firstparty_v1.trust.json
```

This writes:

- `plugin.sig`
- a trust-policy snippet containing the derived public key

Merge that public key into `trusted_publishers.kelvin.json`.

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

From a local KelvinClaw clone:

```bash
scripts/plugin-index-install.sh --index-url <index-url> --plugin <plugin-id>
scripts/plugin-list.sh --json
```

For current hosted first-party packages, prefer validating against a temporary
local index that points at the working-tree tarballs before opening a PR.
