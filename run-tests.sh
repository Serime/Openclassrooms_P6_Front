#!/usr/bin/env bash
set -uo pipefail

readonly RESULTS_DIR="test-results"
readonly REPORT_NAME="junit.xml"
readonly EXIT_TESTS_FAILED=1
readonly EXIT_ENV_ERROR=2
readonly EXIT_REPORT_MISSING=3

usage() {
  cat <<EOF
Usage: $(basename "$0") [--detect] [PROJECT_DIR]

Runs the unit tests of a React or Node.js project and writes a JUnit XML
report to PROJECT_DIR/${RESULTS_DIR}/${REPORT_NAME}.

Options:
  --detect    Print the detected project type (react|node) and exit
  -h, --help  Show this help

Exit codes:
  0  all tests passed
  ${EXIT_TESTS_FAILED}  at least one test failed
  ${EXIT_ENV_ERROR}  missing tool, file or unsupported project
  ${EXIT_REPORT_MISSING}  JUnit report was not generated
EOF
}

log() {
  printf '[run-tests] %s\n' "$*"
}

die() {
  printf '[run-tests] ERROR: %s\n' "$1" >&2
  exit "${2:-$EXIT_ENV_ERROR}"
}

has_dependency() {
  grep -Eq "\"$1\"[[:space:]]*:" package.json
}

detect_project_type() {
  if has_dependency "react"; then
    echo "react"
  elif has_dependency "@nestjs/core" || has_dependency "express"; then
    echo "node"
  else
    echo "unknown"
  fi
}

check_requirements() {
  command -v node >/dev/null 2>&1 || die "node is not installed"
  command -v npm >/dev/null 2>&1 || die "npm is not installed"
  [[ -f package.json ]] || die "package.json not found in $(pwd)"
  [[ -f package-lock.json ]] || die "package-lock.json not found in $(pwd)"
}

install_dependencies() {
  if [[ ! -d node_modules || package-lock.json -nt node_modules/.package-lock.json ]]; then
    log "Installing dependencies with npm ci"
    npm ci --no-audit --no-fund || die "npm ci failed"
  else
    log "Dependencies already installed"
  fi
  [[ -x node_modules/.bin/jest ]] || die "jest is not installed"
  [[ -d node_modules/jest-junit ]] || die "jest-junit is not installed"
}

clean_previous_results() {
  log "Cleaning previous test artifacts"
  rm -rf "$RESULTS_DIR" coverage
  mkdir -p "$RESULTS_DIR"
}

run_tests() {
  local project_type="$1"
  local -a jest_args=(--ci --reporters=default --reporters=jest-junit)

  case "$project_type" in
    react)
      export JEST_JUNIT_SUITE_NAME="react - {filepath}"
      ;;
    node)
      export JEST_JUNIT_SUITE_NAME="node - {filepath}"
      jest_args+=(--runInBand)
      ;;
  esac

  export JEST_JUNIT_OUTPUT_DIR="$RESULTS_DIR"
  export JEST_JUNIT_OUTPUT_NAME="$REPORT_NAME"
  export JEST_JUNIT_CLASSNAME="{classname}"
  export JEST_JUNIT_TITLE="{title}"
  export JEST_JUNIT_ADD_FILE_ATTRIBUTE="true"

  log "Running ${project_type} tests: npm test -- ${jest_args[*]}"
  npm test -- "${jest_args[@]}"
}

main() {
  local mode="run"

  case "${1:-}" in
    --detect) mode="detect"; shift ;;
    -h|--help) usage; exit 0 ;;
  esac

  local project_dir="${1:-.}"
  cd "$project_dir" 2>/dev/null || die "directory not found: $project_dir"
  [[ -f package.json ]] || die "package.json not found in $(pwd)"

  local project_type
  project_type="$(detect_project_type)"
  [[ "$project_type" != "unknown" ]] || die "unsupported project type in $(pwd)"

  if [[ "$mode" == "detect" ]]; then
    echo "$project_type"
    exit 0
  fi

  log "Detected project type: $project_type"
  check_requirements
  install_dependencies
  clean_previous_results

  run_tests "$project_type"
  local status=$?

  [[ -f "$RESULTS_DIR/$REPORT_NAME" ]] || die "JUnit report not generated" "$EXIT_REPORT_MISSING"
  log "JUnit report: $RESULTS_DIR/$REPORT_NAME"

  if [[ $status -ne 0 ]]; then
    log "Tests failed (exit code $status)"
    exit "$EXIT_TESTS_FAILED"
  fi

  log "All tests passed"
  exit 0
}

main "$@"
