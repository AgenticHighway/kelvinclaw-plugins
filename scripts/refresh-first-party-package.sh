#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PLUGIN_ID=""
VERSION=""
KMS_KEY_ID=""
KMS_REGION=""
PUBLISHER_ID="kelvin_firstparty_aws_v1"
INDEX_PATH="${PLUGIN_REPO_ROOT}/index.json"
TRUST_POLICY_PATH="${PLUGIN_REPO_ROOT}/trusted_publishers.kelvin.json"

usage() {
  cat <<'USAGE'
Usage: scripts/refresh-first-party-package.sh --plugin-id <id> --version <version> --kms-key-id <id-or-alias> [options]

Re-signs a committed first-party package tarball with AWS KMS, updates the trust
policy entry for the configured publisher, and refreshes the matching index.json
sha256 entry.

Required:
  --plugin-id <id>        Plugin id, e.g. kelvin.cli
  --version <version>     Package version, e.g. 0.1.1
  --kms-key-id <id>       AWS KMS key id, ARN, or alias

Optional:
  --kms-region <region>   AWS region override
  --publisher-id <id>     Publisher id to embed in plugin.json
  --index-path <path>     Path to index.json
  --trust-policy <path>   Path to trusted_publishers JSON
  -h, --help              Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-id)
      PLUGIN_ID="${2:?missing value for --plugin-id}"
      shift 2
      ;;
    --version)
      VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    --kms-key-id)
      KMS_KEY_ID="${2:?missing value for --kms-key-id}"
      shift 2
      ;;
    --kms-region)
      KMS_REGION="${2:?missing value for --kms-region}"
      shift 2
      ;;
    --publisher-id)
      PUBLISHER_ID="${2:?missing value for --publisher-id}"
      shift 2
      ;;
    --index-path)
      INDEX_PATH="${2:?missing value for --index-path}"
      shift 2
      ;;
    --trust-policy)
      TRUST_POLICY_PATH="${2:?missing value for --trust-policy}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd aws

if [[ -z "${PLUGIN_ID}" || -z "${VERSION}" || -z "${KMS_KEY_ID}" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

PACKAGE_PATH="${PLUGIN_REPO_ROOT}/packages/${PLUGIN_ID}/${VERSION}/${PLUGIN_ID}-${VERSION}.tar.gz"
PACKAGE_URL="https://raw.githubusercontent.com/agentichighway/kelvinclaw-plugins/main/packages/${PLUGIN_ID}/${VERSION}/${PLUGIN_ID}-${VERSION}.tar.gz"
TRUST_POLICY_URL="https://raw.githubusercontent.com/agentichighway/kelvinclaw-plugins/main/trusted_publishers.kelvin.json"

if [[ ! -f "${PACKAGE_PATH}" ]]; then
  echo "Package tarball not found: ${PACKAGE_PATH}" >&2
  exit 1
fi
if [[ ! -f "${INDEX_PATH}" ]]; then
  echo "Index file not found: ${INDEX_PATH}" >&2
  exit 1
fi
if [[ ! -f "${TRUST_POLICY_PATH}" ]]; then
  echo "Trust policy file not found: ${TRUST_POLICY_PATH}" >&2
  exit 1
fi

default_tags_json() {
  case "$1" in
    kelvin.cli)
      printf '%s\n' '["first_party","cli"]'
      ;;
    kelvin.anthropic)
      printf '%s\n' '["first_party","model","anthropic"]'
      ;;
    kelvin.openai)
      printf '%s\n' '["first_party","model","openai"]'
      ;;
    kelvin.openrouter)
      printf '%s\n' '["first_party","model","openrouter"]'
      ;;
    *)
      echo "No default tags are configured for plugin '${1}'." >&2
      exit 1
      ;;
  esac
}

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

PUB_DER_PATH="${WORK_DIR}/public.der"
PUB_PEM_PATH="${WORK_DIR}/public.pem"
PUB_RAW_B64_PATH="${WORK_DIR}/public.raw.b64"
EXTRACT_DIR="${WORK_DIR}/package"
mkdir -p "${EXTRACT_DIR}"

kms_public_key_material "${KMS_KEY_ID}" "${KMS_REGION}" "${PUB_DER_PATH}" "${PUB_PEM_PATH}" "${PUB_RAW_B64_PATH}"
PUB_RAW_B64="$(tr -d '\n' < "${PUB_RAW_B64_PATH}")"

trust_tmp="${WORK_DIR}/trusted_publishers.json"
jq \
  --arg publisher_id "${PUBLISHER_ID}" \
  --arg public_key "${PUB_RAW_B64}" \
  '
    .require_signature = true
    | .publishers = (
        (.publishers // [])
        | if any(.id == $publisher_id) then
            map(if .id == $publisher_id then . + {ed25519_public_key: $public_key} else . end)
          else
            . + [{id: $publisher_id, ed25519_public_key: $public_key}]
          end
      )
  ' "${TRUST_POLICY_PATH}" > "${trust_tmp}"
mv "${trust_tmp}" "${TRUST_POLICY_PATH}"

tar -xzf "${PACKAGE_PATH}" -C "${EXTRACT_DIR}"
MANIFEST_PATH="${EXTRACT_DIR}/plugin.json"
SIGNATURE_PATH="${EXTRACT_DIR}/plugin.sig"

if [[ ! -f "${MANIFEST_PATH}" || ! -d "${EXTRACT_DIR}/payload" ]]; then
  echo "Package must contain plugin.json and payload/." >&2
  exit 1
fi

manifest_id="$(jq -r '.id' "${MANIFEST_PATH}")"
manifest_version="$(jq -r '.version' "${MANIFEST_PATH}")"
entrypoint="$(jq -r '.entrypoint // empty' "${MANIFEST_PATH}")"
entrypoint_sha256="$(jq -r '.entrypoint_sha256 // empty' "${MANIFEST_PATH}")"

if [[ "${manifest_id}" != "${PLUGIN_ID}" ]]; then
  echo "Manifest id '${manifest_id}' does not match requested plugin '${PLUGIN_ID}'." >&2
  exit 1
fi
if [[ "${manifest_version}" != "${VERSION}" ]]; then
  echo "Manifest version '${manifest_version}' does not match requested version '${VERSION}'." >&2
  exit 1
fi
if [[ -z "${entrypoint}" || ! -f "${EXTRACT_DIR}/payload/${entrypoint}" ]]; then
  echo "Manifest entrypoint '${entrypoint}' is missing from payload/." >&2
  exit 1
fi

actual_entrypoint_sha256="$(sha256_file "${EXTRACT_DIR}/payload/${entrypoint}")"
if [[ "${entrypoint_sha256}" != "${actual_entrypoint_sha256}" ]]; then
  echo "Entrypoint sha mismatch for ${PLUGIN_ID}@${VERSION}: manifest=${entrypoint_sha256} actual=${actual_entrypoint_sha256}" >&2
  exit 1
fi

manifest_tmp="${WORK_DIR}/plugin.json"
jq \
  --arg publisher_id "${PUBLISHER_ID}" \
  '.publisher = $publisher_id | .quality_tier = "signed_trusted"' \
  "${MANIFEST_PATH}" > "${manifest_tmp}"
mv "${manifest_tmp}" "${MANIFEST_PATH}"

aws_args=(aws)
if [[ -n "${KMS_REGION}" ]]; then
  aws_args+=(--region "${KMS_REGION}")
fi

signature_b64="$("${aws_args[@]}" kms sign \
  --key-id "${KMS_KEY_ID}" \
  --message "fileb://${MANIFEST_PATH}" \
  --message-type RAW \
  --signing-algorithm ED25519_SHA_512 \
  --output json | jq -er '.Signature')"
printf '%s' "${signature_b64}" > "${SIGNATURE_PATH}"

if ! verify_manifest_signature "${MANIFEST_PATH}" "${SIGNATURE_PATH}" "${PUB_RAW_B64}"; then
  echo "Signature verification failed after KMS signing." >&2
  exit 1
fi

rm -f "${PACKAGE_PATH}"
create_tar_gz "${PACKAGE_PATH}" "${EXTRACT_DIR}" plugin.json payload plugin.sig
package_sha256="$(sha256_file "${PACKAGE_PATH}")"
tags_json="$(default_tags_json "${PLUGIN_ID}")"

index_tmp="${WORK_DIR}/index.json"
jq \
  --arg plugin_id "${PLUGIN_ID}" \
  --arg version "${VERSION}" \
  --arg package_url "${PACKAGE_URL}" \
  --arg package_sha256 "${package_sha256}" \
  --arg trust_policy_url "${TRUST_POLICY_URL}" \
  --argjson tags "${tags_json}" \
  '
    .plugins = (
      (.plugins // [])
      | if any(.id == $plugin_id and .version == $version) then
          map(
            if .id == $plugin_id and .version == $version then
              . + {
                package_url: $package_url,
                sha256: $package_sha256,
                trust_policy_url: $trust_policy_url,
                quality_tier: "signed_trusted",
                tags: $tags
              }
            else
              .
            end
          )
        else
          . + [{
            id: $plugin_id,
            version: $version,
            package_url: $package_url,
            sha256: $package_sha256,
            trust_policy_url: $trust_policy_url,
            quality_tier: "signed_trusted",
            tags: $tags
          }]
        end
    )
  ' "${INDEX_PATH}" > "${index_tmp}"
mv "${index_tmp}" "${INDEX_PATH}"

echo "Refreshed ${PLUGIN_ID}@${VERSION}"
echo "Package SHA-256: ${package_sha256}"
