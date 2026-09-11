#!/usr/bin/env bash
# Verify FreeCAD post-processor naming and staged artifact conventions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

FAIL=0

fail() {
  echo "::error::$1" >&2
  FAIL=1
}

STAGE="${ROOT}/dist/stage-post-processors.sh"
FREECAD_SRC="${ROOT}/post-processors/freecad/nxt_legacy_post.py"
FREECAD_MACHINE_SRC="${ROOT}/post-processors/freecad/nxt_machine_post.py"
MACHINES_DIR="${ROOT}/post-processors/freecad/machines"

if [[ ! -f "${STAGE}" ]]; then
  fail "missing ${STAGE}"
fi
if [[ ! -f "${FREECAD_SRC}" ]]; then
  fail "missing ${FREECAD_SRC}"
fi
if [[ ! -f "${FREECAD_MACHINE_SRC}" ]]; then
  fail "missing ${FREECAD_MACHINE_SRC}"
fi

if ! grep -q 'FREECAD_PY_NAME="nxt-${BUILD_VERSION}_post.py"' "${STAGE}"; then
  fail "stage-post-processors.sh must set FREECAD_PY_NAME=nxt-\${BUILD_VERSION}_post.py"
fi
if ! grep -q 'F360_CPS_NAME="nxt-${BUILD_VERSION}-f360.cps"' "${STAGE}"; then
  fail "stage-post-processors.sh must set F360_CPS_NAME=nxt-\${BUILD_VERSION}-f360.cps"
fi
if ! grep -q 'post-processors/freecad/nxt_legacy_post.py' "${STAGE}"; then
  fail "stage-post-processors.sh must source post-processors/freecad/nxt_legacy_post.py"
fi
if ! grep -q 'FREECAD_MACHINE_PY_NAME="nxt_machine_post.py"' "${STAGE}"; then
  fail "stage-post-processors.sh must set FREECAD_MACHINE_PY_NAME=nxt_machine_post.py (unversioned)"
fi
if ! grep -q 'post-processors/freecad/nxt_machine_post.py' "${STAGE}"; then
  fail "stage-post-processors.sh must source post-processors/freecad/nxt_machine_post.py"
fi
if ! grep -q 'post-processors/fusion-360/nxt.cps' "${STAGE}"; then
  fail "stage-post-processors.sh must source post-processors/fusion-360/nxt.cps"
fi

if ! grep -q 'POST_PREFIX = "nxt-{}".format(RELEASE.VERSION)' "${FREECAD_SRC}"; then
  fail "nxt_post.py must define POST_PREFIX = nxt-{VERSION}"
fi
if ! grep -q 'prog=POST_PREFIX' "${FREECAD_SRC}"; then
  fail "nxt_legacy_post.py argparse prog must use POST_PREFIX"
fi

# FreeCAD's PostProcessorFactory resolves the machine-flow class as
# <filename minus _post.py>.title(), i.e. nxt_machine -> Nxt_Machine. If the
# alias is missing the factory silently falls back to WrapperPost and posting
# fails with "The script does not have an 'export' function".
if ! grep -q '^Nxt_Machine = NxtMachine$' "${FREECAD_MACHINE_SRC}"; then
  fail "nxt_machine_post.py must alias Nxt_Machine = NxtMachine for the post factory"
fi
if ! grep -q '^POST_TYPE = "machine"$' "${FREECAD_MACHINE_SRC}"; then
  fail "nxt_machine_post.py must set POST_TYPE = \"machine\""
fi

# Every shipped machine definition must point at the machine post by file name.
shopt -s nullglob
FCM_FILES=("${MACHINES_DIR}"/*.fcm)
shopt -u nullglob
if [[ "${#FCM_FILES[@]}" -eq 0 ]]; then
  fail "no FreeCAD machine definitions in ${MACHINES_DIR}"
fi
for fcm in "${FCM_FILES[@]}"; do
  if ! grep -q '"file_name": "nxt_machine"' "${fcm}"; then
    fail "$(basename "${fcm}") must set postprocessor.file_name to nxt_machine"
  fi
  if ! grep -q '"nxt_version"' "${fcm}"; then
    fail "$(basename "${fcm}") must set a nxt_version property"
  fi
  if grep -q '%%NXT_VERSION%%' "${fcm}"; then
    fail "$(basename "${fcm}") must set a real nxt_version, not the build placeholder"
  fi
  # Upstream commit 42cc6d0 raised axis precision to 4 decimals to satisfy
  # RRF G2/G3 arc tolerance; 3 reintroduces that defect.
  if ! grep -q '"axis": 4' "${fcm}"; then
    fail "$(basename "${fcm}") must set output.precision.axis to 4 (RRF arc tolerance)"
  fi
done

LEGACY_HITS="$(rg -n 'next_post\.py|next\.cps|-post-freecad\.py' post-processors dist/stage-post-processors.sh 2>/dev/null \
  | grep -Ev '^dist/verify-post-processor-naming\.sh:' \
  || true)"
if [[ -n "${LEGACY_HITS}" ]]; then
  fail "legacy post-processor names (use nxt_* / _post.py)"
  echo "${LEGACY_HITS}" >&2
fi

if [[ "${FAIL}" -ne 0 ]]; then
  echo "verify-post-processor-naming: FAILED" >&2
  exit 1
fi

echo "verify-post-processor-naming: OK"
