#!/usr/bin/env bash
set -euo pipefail

# Re-run repomix recursively.
# Usage: OUT=custom-output.xml STYLE=markdown TARGETS=$'dir1\ndir2' ./repomix-recursive.sh
# Defaults: ROOT=current dir; TARGETS=all first-level subdirectories (ignores the root itself)
# Optional: INSTALL_ALIAS=1 to append alias to ~/.bashrc
# Optional: REPOMIX_MODULE=path/to/repomix/lib/index.js to override module path

# Resolve script path for alias creation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
ALIAS_NAME="repomix-recursive"
ALIAS_LINE="alias ${ALIAS_NAME}='${SCRIPT_PATH}'"

# Default root is the current working directory (override with ROOT=/path)
ROOT="${ROOT:-$(pwd)}"

OUT="${OUT:-repomix-output.xml}"
STYLE="${STYLE:-xml}"
INSTALL_ALIAS="${INSTALL_ALIAS:-1}"
REPOMIX_MODULE="${REPOMIX_MODULE:-file:///usr/local/lib/node_modules/repomix/lib/index.js}"

# If sourced, set the alias immediately for the current shell
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  alias "${ALIAS_NAME}"="${SCRIPT_PATH}"
fi

# If requested, persist the alias into ~/.bashrc (idempotent append)
if [[ "${INSTALL_ALIAS}" == "1" ]]; then
  touch "${HOME}/.bashrc"
  if grep -Fxq "${ALIAS_LINE}" "${HOME}/.bashrc"; then
    printf '%s alias already in ~/.bashrc\n' "${ALIAS_NAME}" >&2
  else
    printf '%s\n' "${ALIAS_LINE}" >> "${HOME}/.bashrc"
    printf 'Added %s alias to ~/.bashrc\n' "${ALIAS_NAME}" >&2
  fi
fi

# Refresh shell aliases for current session
if [[ -f "${HOME}/.bashrc" ]]; then
  # shellcheck disable=SC1090
  . "${HOME}/.bashrc"
fi

# If TARGETS is not provided, use all first-level subdirectories under ROOT
if [[ -z "${TARGETS:-}" ]]; then
  DEFAULT_TARGETS="$(find "${ROOT}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)"
  if [[ -z "${DEFAULT_TARGETS}" ]]; then
    printf 'No subdirectories found under %s; set TARGETS explicitly.\n' "${ROOT}" >&2
    exit 1
  fi
  TARGETS="${DEFAULT_TARGETS}"
fi

missing_dirs=0
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  if [[ ! -d "${ROOT}/${d}" ]]; then
    printf 'Missing directory: %s (ROOT=%s)\n' "$d" "$ROOT" >&2
    missing_dirs=1
  fi
done <<< "${TARGETS}"

if [[ $missing_dirs -ne 0 ]]; then
  printf 'Tip: set ROOT=/path/para/repositorio ./repomix-recursive.sh\n' >&2
  exit 1
fi

ROOT="${ROOT}" TARGETS="${TARGETS}" OUT="${OUT}" STYLE="${STYLE}" INSTALL_ALIAS="${INSTALL_ALIAS}" REPOMIX_MODULE="${REPOMIX_MODULE}" node <<'NODE'
const path = require('node:path');

(async () => {
  const modulePath = process.env.REPOMIX_MODULE;
  let repomix;
  try {
    repomix = await import(modulePath);
  } catch (err) {
    console.error(`Failed to import repomix from ${modulePath}, trying local install...`);
    try {
      repomix = await import('repomix');
    } catch (err2) {
      console.error('Could not load repomix from either module path or local install.');
      console.error(err2);
      process.exit(1);
    }
  }

  const { pack, mergeConfigs } = repomix;

  const cwd = process.env.ROOT;
  const targets = (process.env.TARGETS || '')
    .split('\n')
    .filter(Boolean)
    .map((p) => path.resolve(cwd, p));

  const outputPath = process.env.OUT || 'repomix-output.xml';
  const style = process.env.STYLE || 'xml';

  const config = mergeConfigs(cwd, {}, { output: { style, filePath: outputPath } });

  console.error('Running repomix...');
  try {
    await pack(targets, config, (msg) => console.error(msg));
    console.error(`Done. Output: ${outputPath}`);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
})();
NODE
