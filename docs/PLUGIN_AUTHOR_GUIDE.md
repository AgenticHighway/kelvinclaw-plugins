# Plugin Author Guide

This guide explains how to build, sign, publish, and validate a KelvinClaw plugin
without duplicating runtime/spec details from the main KelvinClaw repository.

## Scope

Use this repo to publish installable plugin artifacts.
Use `kelvinclaw` repo for SDK/runtime implementation and verification tooling.

For the current manual signing flow used by this repo, see:

- [docs/LOCAL_SIGNING_AND_PUBLISHING.md](LOCAL_SIGNING_AND_PUBLISHING.md)

## Prerequisites

1. A Rust/WASM plugin project that builds to a `.wasm` file.
2. A clone of `agentichighway/kelvinclaw` (for signing/install scripts).
3. Ed25519 keypair for plugin signing.
4. `openssl`, `jq`, and `tar`.

## Choose Runtime Type

1. `wasm_tool_v1` for tool plugins.
2. `wasm_model_v1` for model provider plugins.

For new model plugins, prefer host-routed manifests:

- declare `provider_profile` such as `openai.responses` or `anthropic.messages`
- include `network_egress` when the plugin intentionally relies on outbound model transport
- keep `network_allow_hosts` explicit and minimal

Canonical runtime/capability rules:

- https://github.com/agentichighway/kelvinclaw/blob/main/docs/PLUGIN_INSTALL_FLOW.md
- https://github.com/agentichighway/kelvinclaw/blob/main/docs/model-plugin-abi.md

## Package Layout

Required package structure:

```text
plugin.json
plugin.sig
payload/
  <entrypoint>.wasm
```

`plugin.json` templates are in:

- `templates/plugin.tool.wasm_tool_v1.json`
- `templates/plugin.model.wasm_model_v1.json`

Current templates also include recommended `quality_tier` defaults and model
`provider_profile` usage.

## Build and Assemble

Example assembly flow:

```bash
# 1) build your plugin wasm in your plugin source repo
cargo build --release --target wasm32-unknown-unknown

# 2) create package staging directory
mkdir -p /tmp/my-plugin/payload
cp path/to/your.wasm /tmp/my-plugin/payload/
cp templates/plugin.tool.wasm_tool_v1.json /tmp/my-plugin/plugin.json
```

Set `entrypoint_sha256` in `plugin.json` to the SHA-256 of the `.wasm` entrypoint.

## Sign Manifest

Use the KelvinClaw signing script:

```bash
cd /path/to/kelvinclaw
scripts/plugin-sign.sh \
  --manifest /tmp/my-plugin/plugin.json \
  --private-key /path/to/your-ed25519-private.pem \
  --publisher-id your_publisher_id \
  --trust-policy-out /tmp/your-publisher-trust.json
```

This generates `plugin.sig` for distribution and a trust-policy snippet.

Do not commit private keys into either repository. Commit only the matching
public key in `trusted_publishers.kelvin.json`.

## Create Distribution Tarball

Use GNU tar format where possible (no platform-specific xattrs):

```bash
tar -czf your.plugin.id-1.0.0.tar.gz -C /tmp/my-plugin plugin.json payload plugin.sig
```

Compute package SHA-256 and record it for `index.json`.

## Publish to This Repo

1. Add tarball:
   - `packages/your.plugin.id/1.0.0/your.plugin.id-1.0.0.tar.gz`
2. Add/merge publisher key in `trusted_publishers.kelvin.json`.
3. Add entry to `index.json` with:
   - `id`, `version`, `package_url`, `sha256`
   - optional `trust_policy_url` (recommended)
   - optional `quality_tier` and `tags` (recommended)

Index entry template:

- `templates/index.entry.v1.json`

## Validate Before PR

From a KelvinClaw clone:

```bash
# install from your index entry
scripts/plugin-index-install.sh --index-url <index-url> --plugin your.plugin.id

# list installed plugin
scripts/plugin-list.sh --json
```

Recommended checks:

1. Install succeeds with SHA verification.
2. Runtime admission succeeds (signature + capability checks).
3. Plugin behavior matches declared capability scopes and fails closed.

If you lose a signing key, do not overwrite an old publisher entry in place for
already-published artifacts. Use a new publisher id for new releases and append
its public key to the trust policy.

## Security Checklist

1. Use least-privilege capability scopes.
2. Keep `network_allow_hosts` explicit and minimal.
3. Keep `entrypoint_sha256` present and correct.
4. Use unique publisher id and managed signing keys.
5. Rotate signing keys when needed and update trust policy deliberately.

## Notes

This repo is artifact-first, not source-first. Plugin source code can live in
any repository; this repo is for installable packages and metadata.
