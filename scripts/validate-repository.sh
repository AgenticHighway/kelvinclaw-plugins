#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PLUGIN_ID=""
VERSION=""
INDEX_PATH="${PLUGIN_REPO_ROOT}/index.json"
TRUST_POLICY_PATH="${PLUGIN_REPO_ROOT}/trusted_publishers.kelvin.json"

usage() {
  cat <<'USAGE'
Usage: scripts/validate-repository.sh [options]

Validates package tarballs, index entries, and manifest signatures in the local
kelvinclaw-plugins repository.

Optional:
  --plugin-id <id>        Validate only one plugin id
  --version <version>     Validate only one version
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

if [[ ! -f "${INDEX_PATH}" || ! -f "${TRUST_POLICY_PATH}" ]]; then
  echo "Index and trust policy files must exist." >&2
  exit 1
fi

jq -e '.require_signature == true' "${TRUST_POLICY_PATH}" >/dev/null

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

filter_expr='.plugins[]'
if [[ -n "${PLUGIN_ID}" ]]; then
  filter_expr+=' | select(.id == $plugin_id)'
fi
if [[ -n "${VERSION}" ]]; then
  filter_expr+=' | select(.version == $version)'
fi

plugin_rows="$(
  jq -r \
    --arg plugin_id "${PLUGIN_ID}" \
    --arg version "${VERSION}" \
    "${filter_expr} | [.id, .version, .sha256, .package_url, (.trust_policy_url // \"\")] | @tsv" \
    "${INDEX_PATH}"
)"

if [[ -z "${plugin_rows}" ]]; then
  echo "No index entries matched the requested selection." >&2
  exit 1
fi

while IFS=$'\t' read -r entry_id entry_version entry_sha256 entry_package_url entry_trust_policy_url; do
  [[ -n "${entry_id}" ]] || continue

  package_rel="packages/${entry_id}/${entry_version}/${entry_id}-${entry_version}.tar.gz"
  package_path="${PLUGIN_REPO_ROOT}/${package_rel}"
  expected_package_url="https://raw.githubusercontent.com/agentichighway/kelvinclaw-plugins/main/${package_rel}"
  expected_trust_policy_url="https://raw.githubusercontent.com/agentichighway/kelvinclaw-plugins/main/trusted_publishers.kelvin.json"

  if [[ "${entry_package_url}" != "${expected_package_url}" ]]; then
    echo "Unexpected package_url for ${entry_id}@${entry_version}: ${entry_package_url}" >&2
    exit 1
  fi
  if [[ -n "${entry_trust_policy_url}" && "${entry_trust_policy_url}" != "${expected_trust_policy_url}" ]]; then
    echo "Unexpected trust_policy_url for ${entry_id}@${entry_version}: ${entry_trust_policy_url}" >&2
    exit 1
  fi
  if [[ ! -f "${package_path}" ]]; then
    echo "Indexed package is missing: ${package_path}" >&2
    exit 1
  fi

  actual_sha256="$(sha256_file "${package_path}")"
  if [[ "${actual_sha256}" != "${entry_sha256}" ]]; then
    echo "SHA mismatch for ${entry_id}@${entry_version}: index=${entry_sha256} actual=${actual_sha256}" >&2
    exit 1
  fi

  extract_dir="${WORK_DIR}/${entry_id}-${entry_version}"
  mkdir -p "${extract_dir}"
  tar -xzf "${package_path}" -C "${extract_dir}"

  manifest_path="${extract_dir}/plugin.json"
  signature_path="${extract_dir}/plugin.sig"
  payload_dir="${extract_dir}/payload"
  if [[ ! -f "${manifest_path}" || ! -f "${signature_path}" || ! -d "${payload_dir}" ]]; then
    echo "Package ${entry_id}@${entry_version} is missing plugin.json, plugin.sig, or payload/." >&2
    exit 1
  fi

  manifest_id="$(jq -r '.id' "${manifest_path}")"
  manifest_version="$(jq -r '.version' "${manifest_path}")"
  manifest_publisher="$(jq -r '.publisher // empty' "${manifest_path}")"
  entrypoint="$(jq -r '.entrypoint // empty' "${manifest_path}")"
  entrypoint_sha256="$(jq -r '.entrypoint_sha256 // empty' "${manifest_path}")"

  if [[ "${manifest_id}" != "${entry_id}" || "${manifest_version}" != "${entry_version}" ]]; then
    echo "Manifest mismatch inside ${package_rel}." >&2
    exit 1
  fi
  if [[ -z "${manifest_publisher}" ]]; then
    echo "Manifest publisher is missing for ${entry_id}@${entry_version}." >&2
    exit 1
  fi
  if [[ -z "${entrypoint}" || ! -f "${payload_dir}/${entrypoint}" ]]; then
    echo "Entrypoint '${entrypoint}' is missing for ${entry_id}@${entry_version}." >&2
    exit 1
  fi

  actual_entrypoint_sha256="$(sha256_file "${payload_dir}/${entrypoint}")"
  if [[ "${actual_entrypoint_sha256}" != "${entrypoint_sha256}" ]]; then
    echo "Entrypoint sha mismatch for ${entry_id}@${entry_version}." >&2
    exit 1
  fi

  publisher_key_b64="$(jq -r --arg publisher "${manifest_publisher}" '.publishers[] | select(.id == $publisher) | .ed25519_public_key' "${TRUST_POLICY_PATH}")"
  if [[ -z "${publisher_key_b64}" ]]; then
    echo "Publisher '${manifest_publisher}' is missing from trust policy." >&2
    exit 1
  fi

  if ! verify_manifest_signature "${manifest_path}" "${signature_path}" "${publisher_key_b64}"; then
    echo "Signature verification failed for ${entry_id}@${entry_version}." >&2
    exit 1
  fi

  echo "Validated ${entry_id}@${entry_version}"
done <<< "${plugin_rows}"
