#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: generate_btf_from_rpm.sh [-o OUT_DIR] [-f] KERNEL_DEBUGINFO_RPM

Generate a detached BTF file (.vmlinux) from a kernel-debuginfo RPM using pahole.

Options:
  -o OUT_DIR   Output directory for the generated .vmlinux file (default: current script directory)
  -f           Force overwrite if the output .vmlinux file already exists
  -h           Show this help

Examples:
  ./generate_btf_from_rpm.sh kernel-debuginfo-4.19.90-2107.6.0.0100.oe1.bclinux.x86_64.rpm
  ./generate_btf_from_rpm.sh -o ./ /path/to/kernel-debuginfo-*.rpm

This script expects the following tools:
  - pahole (for encoding BTF)
  - rpm2cpio and cpio (to extract the RPM)
  - optional: bpftool (to validate the generated BTF)
USAGE
}

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=0

while getopts ":o:fh" opt; do
  case "$opt" in
    o) OUT_DIR="${OPTARG}" ;;
    f) FORCE=1 ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage; exit 1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [[ $# -ne 1 ]]; then
  echo "Error: exactly one kernel-debuginfo RPM must be provided" >&2
  usage
  exit 1
fi

RPM_PATH="${1}"
if [[ ! -f "${RPM_PATH}" ]]; then
  echo "Error: RPM not found: ${RPM_PATH}" >&2
  exit 1
fi

# Tool checks
need_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required tool not found in PATH: $1" >&2
    exit 2
  fi
}

need_tool pahole
need_tool rpm2cpio
need_tool cpio

mkdir -p "${OUT_DIR}"

RPM_BASENAME="$(basename -- "${RPM_PATH}")"

# Derive output filename from RPM name: kernel-debuginfo-<KVER>.rpm -> <KVER>.vmlinux
# Keep arch suffix as part of <KVER> if present (e.g., ...x86_64)
KVER_WITH_ARCH="${RPM_BASENAME}" \
  && KVER_WITH_ARCH="${KVER_WITH_ARCH#kernel-debuginfo-}" \
  && KVER_WITH_ARCH="${KVER_WITH_ARCH%.rpm}"

OUT_FILE="${OUT_DIR}/${KVER_WITH_ARCH}.vmlinux"

if [[ -f "${OUT_FILE}" && "${FORCE}" -ne 1 ]]; then
  echo "Output already exists: ${OUT_FILE} (use -f to overwrite)"
  exit 0
fi

TMPDIR="$(mktemp -d -t btfgen.XXXXXXXX)"
cleanup() { rm -rf "${TMPDIR}"; }
trap cleanup EXIT

echo "Extracting RPM to ${TMPDIR} ..."
(
  cd "${TMPDIR}"
  rpm2cpio "${RPM_PATH}" | cpio -idmv --no-absolute-filenames
)

# Locate vmlinux file inside extracted payload
VMLINUX_CANDIDATES=()
while IFS= read -r -d '' f; do VMLINUX_CANDIDATES+=("$f"); done < <(find "${TMPDIR}" -type f \( -name vmlinux -o -name 'vmlinux-*' -o -name 'vmlinux*.xz' -o -name 'vmlinux*.gz' \) -print0)

if [[ ${#VMLINUX_CANDIDATES[@]} -eq 0 ]]; then
  echo "Error: no vmlinux file found in RPM payload" >&2
  find "${TMPDIR}" -maxdepth 4 -type d -print >&2
  exit 3
fi

# Prefer uncompressed vmlinux under usr/lib/debug/lib/modules/*/vmlinux, else decompress if needed
pick_vmlinux() {
  local cand
  for cand in "${VMLINUX_CANDIDATES[@]}"; do
    if [[ "${cand}" =~ /usr/lib/debug/lib/modules/.*/vmlinux$ ]]; then
      echo "${cand}"; return 0
    fi
  done
  for cand in "${VMLINUX_CANDIDATES[@]}"; do
    if [[ "${cand}" =~ /usr/lib/debug/boot/vmlinux-.*$ ]]; then
      echo "${cand}"; return 0
    fi
  done
  # Fallback: pick the largest candidate
  local largest=""
  if [[ ${#VMLINUX_CANDIDATES[@]} -gt 0 ]]; then
    largest=$(printf '%s\0' "${VMLINUX_CANDIDATES[@]}" | xargs -0 ls -lS 2>/dev/null | awk '{print $NF; exit}')
  fi
  if [[ -z "${largest}" ]]; then
    echo "Error: failed to select a vmlinux candidate (no files found or pipeline failed)" >&2
    return 1
  fi
  printf '%s\n' "${largest}"
}

# Safely capture selection even under 'set -e'
set +e
SELECTED_VMLINUX="$(pick_vmlinux)"
rc=$?
set -e
if [[ ${rc} -ne 0 || -z "${SELECTED_VMLINUX}" ]]; then
  echo "Error: failed to determine vmlinux file from RPM payload" >&2
  exit 3
fi
echo "Found vmlinux candidate: ${SELECTED_VMLINUX}"

# Decompress if necessary
case "${SELECTED_VMLINUX}" in
  *.xz)
    if command -v unxz >/dev/null 2>&1; then
      echo "Decompressing ${SELECTED_VMLINUX} ..."
      unxz -v "${SELECTED_VMLINUX}"
      SELECTED_VMLINUX="${SELECTED_VMLINUX%.xz}"
    else
      echo "Error: ${SELECTED_VMLINUX} is xz-compressed and 'unxz' is not available" >&2
      exit 4
    fi
    ;;
  *.gz)
    if command -v gzip >/dev/null 2>&1; then
      echo "Decompressing ${SELECTED_VMLINUX} ..."
      gunzip -v "${SELECTED_VMLINUX}"
      SELECTED_VMLINUX="${SELECTED_VMLINUX%.gz}"
    else
      echo "Error: ${SELECTED_VMLINUX} is gzip-compressed and 'gzip' is not available" >&2
      exit 4
    fi
    ;;
esac

echo "Generating detached BTF: ${OUT_FILE}"
pahole --btf_encode_detached "${OUT_FILE}" "${SELECTED_VMLINUX}"

# Quick validation (optional)
if command -v bpftool >/dev/null 2>&1; then
  echo "Validating generated BTF with bpftool ..."
  if ! bpftool btf dump file "${OUT_FILE}" >/dev/null 2>&1; then
    echo "Warning: bpftool failed to parse generated BTF (file: ${OUT_FILE})" >&2
  fi
fi

echo "Done. Generated: ${OUT_FILE}"
