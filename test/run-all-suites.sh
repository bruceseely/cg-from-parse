#!/usr/bin/env bash
#
# run-all-suites.sh -- run the whole cg-from-parse stack's test suites, each in
# its OWN fresh SBCL process, and report one combined pass/fail.
#
# cg-from-parse sits on top of both parsifal (the parser) and cgraph (the CG
# engine); a regression in either shows up here as an extraction failure. This
# script gives a single green/red gate over all of it:
#
#   parsifal             -- unit suite (pa::test-all)
#   parsifal-integration -- gram1/gram3/gram4/... grammar tests (own runner)
#   cgraph               -- engine suite (cg::test-all)
#   cg-from-parse        -- headless extractor integration suite
#
# Why separate processes rather than one image: the suites share global mutable
# state that would cross-contaminate if run together -- the cgraph TYPE CATALOG,
# and (worse) parsifal's grammar/dictionary/parser globals, which make the
# integration tests fail out of isolation. Each suite gets its own SBCL; the
# integration suite goes further and runs each test file in its own process (see
# parsifal/test/integration/run-integration.sh). The cgraph run points
# *cgraph-types-directory* at a throwaway temp dir so your real ~/.cgraph is
# never touched. Systems are located via ASDF, so no repo paths are hard-coded.
#
# Usage:   test/run-all-suites.sh
# Env:     SBCL=/path/to/sbcl   (default: sbcl on PATH)
# Exit:    0 iff every suite passed; 1 otherwise.

set -u

SBCL="${SBCL:-sbcl}"
export SBCL                        # child runners (parsifal integration) inherit
COMMON=(--non-interactive --disable-debugger)

# Isolated, writable types dir for cgraph's with-test-types symlink swap.
# Trailing slash: cgraph builds "~aconcept-types.lisp" straight off it.
CGTYPES_DIR="$(mktemp -d)/"
export CGTYPES_DIR
cleanup() { rm -rf "${CGTYPES_DIR%/}"; }
trap cleanup EXIT

# Locate parsifal (for its integration runner) via ASDF, wherever it lives.
PARSIFAL_DIR="$("$SBCL" "${COMMON[@]}" \
  --eval '(ql:quickload :parsifal :silent t)' \
  --eval '(progn (write-string (namestring (asdf:system-source-directory :parsifal)))
                 (terpri) (finish-output))' \
  2>/dev/null | tail -1)"
INTEG_SH="${PARSIFAL_DIR}test/integration/run-integration.sh"

declare -a NAMES RESULTS

# run_suite NAME COMMAND...  -- run COMMAND, record its exit code under NAME.
run_suite() {
  local name="$1"; shift
  echo
  echo "============================================================"
  echo "  ${name}"
  echo "============================================================"
  "$@"
  local code=$?
  NAMES+=("$name")
  RESULTS+=("$code")
  if [ "$code" -eq 0 ]; then
    echo "-> ${name}: PASS"
  else
    echo "-> ${name}: FAIL (exit ${code})"
  fi
}

# 1. parsifal -- unit suite (pa::test-all).
run_suite "parsifal" \
  "$SBCL" "${COMMON[@]}" \
  --eval '(ql:quickload :parsifal :silent t)' \
  --eval '(sb-ext:exit :code (if (uiop:symbol-call "PARSIFAL" "TEST-ALL" t) 0 1))'

# 2. parsifal integration -- gram1/gram3/gram4/... grammar tests. Its runner
#    runs each test file in its own process (they cross-contaminate in one image)
#    and exits non-zero if any fail.
if [ -f "$INTEG_SH" ]; then
  run_suite "parsifal-integration" bash "$INTEG_SH"
else
  echo "!! parsifal-integration: runner not found at ${INTEG_SH}" >&2
  NAMES+=("parsifal-integration"); RESULTS+=(1)
fi

# 3. cgraph -- engine suite (cg::test-all) against an ISOLATED test-types
#    catalog. test-all.lisp is not in cgraph's asd, so load it explicitly.
#    NB: *package* MUST be :conceptual-graphs -- cgraph's tests READ graph
#    strings and type labels in the current package, so from CL-USER those
#    symbols intern as CL-USER::ACT etc. and every type lookup misses.
run_suite "cgraph" \
  "$SBCL" "${COMMON[@]}" \
  --eval '(ql:quickload :cgraph :silent t)' \
  --eval '(in-package :conceptual-graphs)' \
  --eval '(setf *cgraph-types-directory* (uiop:getenv "CGTYPES_DIR"))' \
  --eval '(handler-bind ((warning (function muffle-warning)))
            (load (merge-pathnames "test/test-all.lisp"
                                   (asdf:system-source-directory :cgraph))))' \
  --eval '(sb-ext:exit :code (if (test-all t) 0 1))'

# 4. cg-from-parse -- headless integration suite (run-headless-tests, i.e. the
#    real extractor coverage; cfp::test-all alone is just the case-role unit
#    check). run-headless.lisp exits 1 on any failure, 0 (fall-through) on all-pass.
run_suite "cg-from-parse" \
  "$SBCL" "${COMMON[@]}" \
  --eval '(ql:quickload :swank :silent t)' \
  --eval '(ql:quickload :cg-from-parse :silent t)' \
  --eval '(load (merge-pathnames "test/run-headless.lisp"
                                 (asdf:system-source-directory :cg-from-parse)))'

echo
echo "============================================================"
echo "  SUMMARY"
echo "============================================================"
overall=0
for i in "${!NAMES[@]}"; do
  if [ "${RESULTS[$i]}" -eq 0 ]; then
    status="PASS"
  else
    status="FAIL"
    overall=1
  fi
  printf "  %-22s %s\n" "${NAMES[$i]}" "$status"
done
echo
if [ "$overall" -eq 0 ]; then
  echo "ALL SUITES PASS"
else
  echo "SOME SUITES FAILED"
fi
exit "$overall"
