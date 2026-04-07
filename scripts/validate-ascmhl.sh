#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INGEST_PACKAGE_DIR="${ROOT_DIR}/packages/ingest-daemon"
XSD_DIR="${SCRIPT_DIR}/ascmhl-xsd"
MANIFEST_XSD="${XSD_DIR}/ASCMHL.xsd"
CHAIN_XSD="${XSD_DIR}/ASCMHLDirectory.xsd"

FIXTURE_DIR="${1:-${SLATE_MHL_FIXTURE_DIR:-}}"
if [[ -z "${FIXTURE_DIR}" ]]; then
  FIXTURE_DIR="$(mktemp -d)/slate-mhl-fixtures"
fi

generate_fixture_if_needed() {
  local existing_count
  existing_count="$(python3 - "${FIXTURE_DIR}" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
print(sum(1 for _ in root.rglob("*.mhl")) if root.exists() else 0)
PY
)"
  if [[ "${existing_count}" != "0" ]]; then
    return
  fi

  echo "No ASC MHL fixtures found under ${FIXTURE_DIR}; generating fixture via ingest test..."
  SLATE_MHL_FIXTURE_DIR="${FIXTURE_DIR}" \
    swift test --package-path "${INGEST_PACKAGE_DIR}" \
    --filter IngestDaemonTests/testVerifiedCopyEngineProducesMatchingHashesAndManifest
}

validate_with_xmllint() {
  local file="$1"
  local schema="$2"
  xmllint --noout --schema "${schema}" "${file}" >/dev/null
}

validate_well_formed_python() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys
import xml.etree.ElementTree as ET
path = sys.argv[1]
ET.parse(path)
print(f"well-formed: {path}")
PY
}

main() {
  generate_fixture_if_needed

  local manifests chain_files
  manifests="$(python3 - "${FIXTURE_DIR}" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
if root.exists():
    for path in sorted(root.rglob("*.mhl")):
        print(path)
PY
)"
  chain_files="$(python3 - "${FIXTURE_DIR}" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
if root.exists():
    for path in sorted(root.rglob("ascmhl_chain.xml")):
        print(path)
PY
)"

  if [[ -z "${manifests}" && -z "${chain_files}" ]]; then
    echo "No ASC MHL files found in ${FIXTURE_DIR}"
    exit 1
  fi

  local has_xmllint="false"
  if command -v xmllint >/dev/null 2>&1; then
    has_xmllint="true"
  fi

  if [[ "${has_xmllint}" == "true" ]]; then
    echo "Validating ASC MHL XML against XSD..."
    while IFS= read -r manifest; do
      [[ -z "${manifest}" ]] && continue
      validate_with_xmllint "${manifest}" "${MANIFEST_XSD}"
      echo "validated manifest: ${manifest}"
    done <<< "${manifests}"

    while IFS= read -r chain; do
      [[ -z "${chain}" ]] && continue
      validate_with_xmllint "${chain}" "${CHAIN_XSD}"
      echo "validated chain: ${chain}"
    done <<< "${chain_files}"
  else
    echo "xmllint not found; falling back to XML well-formed checks."
    while IFS= read -r manifest; do
      [[ -z "${manifest}" ]] && continue
      validate_well_formed_python "${manifest}"
    done <<< "${manifests}"
    while IFS= read -r chain; do
      [[ -z "${chain}" ]] && continue
      validate_well_formed_python "${chain}"
    done <<< "${chain_files}"
  fi

  echo "ASC MHL validation complete (${FIXTURE_DIR})."
}

main "$@"
