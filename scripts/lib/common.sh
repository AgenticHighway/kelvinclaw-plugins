#!/usr/bin/env bash
set -euo pipefail

PLUGIN_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "Missing required command: ${name}" >&2
    exit 1
  fi
}

resolve_openssl_cmd() {
  local candidate=""
  for candidate in \
    "/opt/homebrew/opt/openssl@3/bin/openssl" \
    "/usr/local/opt/openssl@3/bin/openssl"
  do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  printf '%s\n' "openssl"
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
    return 0
  fi
  echo "Missing required command: shasum or sha256sum" >&2
  exit 1
}

ed25519_raw_public_key_b64_to_pem() {
  local raw_b64="$1"
  local out_pem="$2"
  local work_dir
  work_dir="$(mktemp -d)"
  local raw_path="${work_dir}/public.raw"
  local der_path="${work_dir}/public.der"
  local raw_hex=""

  printf '%s' "${raw_b64}" | "${OPENSSL_BIN}" base64 -d -A > "${raw_path}"
  raw_hex="$(xxd -p -c 256 "${raw_path}" | tr -d '\n')"
  if [[ ${#raw_hex} -ne 64 ]]; then
    echo "Expected a raw 32-byte Ed25519 public key." >&2
    rm -rf "${work_dir}"
    exit 1
  fi
  printf '%s' "302a300506032b6570032100${raw_hex}" | xxd -r -p > "${der_path}"
  "${OPENSSL_BIN}" pkey -pubin -inform DER -in "${der_path}" -outform PEM -out "${out_pem}" >/dev/null 2>&1
  rm -rf "${work_dir}"
}

kms_public_key_material() {
  local kms_key_id="$1"
  local kms_region="$2"
  local der_out="$3"
  local pem_out="$4"
  local raw_b64_out="$5"
  local aws_response=""
  local key_spec=""
  local pub_der_b64=""
  local pub_hex=""
  local aws_args=(aws)

  if [[ -n "${kms_region}" ]]; then
    aws_args+=(--region "${kms_region}")
  fi
  aws_args+=(
    kms
    get-public-key
    --key-id "${kms_key_id}"
    --output json
  )

  aws_response="$("${aws_args[@]}")"
  key_spec="$(printf '%s' "${aws_response}" | jq -r '.KeySpec // empty')"
  if [[ "${key_spec}" != "ECC_NIST_EDWARDS25519" ]]; then
    echo "KMS key '${kms_key_id}' must use KeySpec ECC_NIST_EDWARDS25519; got '${key_spec}'." >&2
    exit 1
  fi

  pub_der_b64="$(printf '%s' "${aws_response}" | jq -er '.PublicKey')"
  printf '%s' "${pub_der_b64}" | "${OPENSSL_BIN}" base64 -d -A > "${der_out}"
  "${OPENSSL_BIN}" pkey -pubin -inform DER -in "${der_out}" -outform PEM -out "${pem_out}" >/dev/null 2>&1

  pub_hex="$(
    "${OPENSSL_BIN}" pkey -pubin -inform DER -in "${der_out}" -text -noout 2>/dev/null \
      | awk '
        /^pub:/ {capture=1; next}
        capture && /^[[:space:]]*$/ {capture=0; next}
        capture {gsub(/[ :]/, "", $0); printf "%s", $0}
      '
  )"

  if [[ ${#pub_hex} -ne 64 ]]; then
    echo "Failed to derive a raw 32-byte Ed25519 public key from KMS output." >&2
    exit 1
  fi

  printf '%s' "${pub_hex}" | xxd -r -p | "${OPENSSL_BIN}" base64 -A > "${raw_b64_out}"
}

verify_manifest_signature() {
  local manifest_path="$1"
  local signature_path="$2"
  local raw_pub_b64="$3"
  local work_dir
  work_dir="$(mktemp -d)"
  local pub_pem="${work_dir}/public.pem"
  local sig_bin="${work_dir}/plugin.sig.bin"

  ed25519_raw_public_key_b64_to_pem "${raw_pub_b64}" "${pub_pem}"
  printf '%s' "$(tr -d '\n' < "${signature_path}")" | "${OPENSSL_BIN}" base64 -d -A > "${sig_bin}"
  if ! "${OPENSSL_BIN}" pkeyutl -verify -pubin -inkey "${pub_pem}" -rawin -in "${manifest_path}" -sigfile "${sig_bin}" >/dev/null 2>&1; then
    rm -rf "${work_dir}"
    return 1
  fi
  rm -rf "${work_dir}"
}

OPENSSL_BIN="$(resolve_openssl_cmd)"
require_cmd awk
require_cmd jq
require_cmd openssl
require_cmd tar
require_cmd xxd
