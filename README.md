# kelvinclaw-plugins

Distribution repository for prebuilt, signed KelvinClaw plugin packages.

This repo is intentionally focused on publish/install artifacts, not plugin source code:

- `index.json` (plugin index, schema `v1`)
- `packages/<plugin_id>/<version>/<plugin_id>-<version>.tar.gz`
- `trusted_publishers.kelvin.json` (publisher trust policy)

Currently published first-party packages:

- `kelvin.cli`
- `kelvin.anthropic`
- `kelvin.openai`
- `kelvin.openrouter`

Upstream plugin ids that are documented in the main repo but not yet published here:

- `kelvin.browser.automation`

## For Plugin Developers

Use this guide first:

- [docs/PLUGIN_AUTHOR_GUIDE.md](docs/PLUGIN_AUTHOR_GUIDE.md)
- [docs/LOCAL_SIGNING_AND_PUBLISHING.md](docs/LOCAL_SIGNING_AND_PUBLISHING.md)

AgenticHighway first-party releases now target AWS KMS-backed Ed25519 signing via
the private `REDACTED_INTERNAL_REPO` repo. The default release path is GitHub Actions OIDC on
Blacksmith runners, with local `AWS_PROFILE=REDACTED_AWS_PROFILE` signing kept as the
manual fallback. Community publishers can continue using local PEM signing.

For local community development, use the public authoring flow in the
`kelvinclaw` repo first. Unsigned local plugins are supported there and Kelvin
warns on install instead of blocking them. This repo is only for published
package artifacts and trust/index metadata.

Repo automation:

- `.github/workflows/validate-repository.yml`
- `.github/workflows/publish-first-party-package.yml`
- `scripts/validate-repository.sh`
- `scripts/refresh-first-party-package.sh`

Templates:

- [templates/plugin.tool.wasm_tool_v1.json](templates/plugin.tool.wasm_tool_v1.json)
- [templates/plugin.model.wasm_model_v1.json](templates/plugin.model.wasm_model_v1.json)
- [templates/index.entry.v1.json](templates/index.entry.v1.json)

## KelvinClaw References

This repo does not duplicate SDK/runtime specification docs. Canonical references:

- [KelvinClaw: Plugin Install Flow](https://github.com/agentichighway/kelvinclaw/blob/main/docs/PLUGIN_INSTALL_FLOW.md)
- [KelvinClaw: Model Plugin ABI](https://github.com/agentichighway/kelvinclaw/blob/main/docs/model-plugin-abi.md)
- [KelvinClaw: Plugin Index Schema](https://github.com/agentichighway/kelvinclaw/blob/main/docs/plugin-index-schema.md)
- [KelvinClaw: Trusted Executive + WASM](https://github.com/agentichighway/kelvinclaw/blob/main/docs/trusted-executive-wasm.md)

## Installers That Consume This Repo

- `scripts/install-kelvin-cli-plugin.sh`
- `scripts/install-kelvin-openai-plugin.sh`
- `scripts/install-kelvin-anthropic-plugin.sh`
- `scripts/install-kelvin-browser-plugin.sh`
- `scripts/plugin-index-install.sh`

All are in the KelvinClaw repository.
