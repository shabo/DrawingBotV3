#!/usr/bin/env bash
# Tests for ci/junit-summary.sh.
# Plain bash, no test framework. Fixtures are in ci/test/fixtures/.
# Run: bash ci/test/junit-summary.test.sh

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
sut="$root/ci/junit-summary.sh"
fix="$here/fixtures"

pass=0
fail=0
out=""
rc=0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Run one command. Save the output in out and the exit code in rc.
run() {
    out=$("$@" 2>&1)
    rc=$?
}

ok() {
    pass=$((pass + 1))
    echo "ok $((pass + fail)) - $1"
}

notok() {
    fail=$((fail + 1))
    echo "not ok $((pass + fail)) - $1"
    if [ -n "$out" ]; then
        printf '%s\n' "$out" | sed 's/^/    # /'
    fi
}

# Check the saved exit code. Usage: check_rc <want> <label>
check_rc() {
    if [ "$rc" -eq "$1" ]; then
        ok "$2"
    else
        notok "$2 (exit $rc, want $1)"
    fi
}

# Check that the saved output matches an extended regex. Usage: check_out <regex> <label>
check_out() {
    if printf '%s\n' "$out" | grep -Eq -- "$1"; then
        ok "$2"
    else
        notok "$2 (no match for: $1)"
    fi
}

echo "# sut: $sut"

# Case 1 (Happy): 2 files, all tests pass. Totals printed, exit 0.
echo "# case 1: two files, all pass"
run bash "$sut" "$fix/pass"
check_rc 0 "case 1: exit 0"
check_out 'files=2( |$)' "case 1: counts 2 files"
check_out 'tests=5( |$)' "case 1: sums tests to 5"
check_out 'failures=0( |$)' "case 1: reports 0 failures"
check_out 'errors=0( |$)' "case 1: reports 0 errors"
check_out 'skipped=0( |$)' "case 1: reports 0 skipped"

# Case 2 (Happy): skipped tests. Skipped counted, exit 0.
echo "# case 2: skipped tests"
run bash "$sut" "$fix/skipped"
check_rc 0 "case 2: exit 0"
check_out 'tests=4( |$)' "case 2: sums tests to 4"
check_out 'skipped=2( |$)' "case 2: counts 2 skipped"

# Case 3 (Sad): 1 failure. Exit 1, failing case name printed.
echo "# case 3: one failure"
run bash "$sut" "$fix/failure"
check_rc 1 "case 3: exit 1"
check_out 'failures=1( |$)' "case 3: counts 1 failure"
check_out '^FAILED: drawingbot\.example\.BrokenTest\.testAddsTwoNumbers$' "case 3: prints the failing testcase name"

# Case 4 (Sad): 1 error. Exit 1, failing case name printed.
echo "# case 4: one error"
run bash "$sut" "$fix/error"
check_rc 1 "case 4: exit 1"
check_out 'errors=1( |$)' "case 4: counts 1 error"
check_out '^FAILED: drawingbot\.example\.ErrorTest\.testThrows$' "case 4: prints the erroring testcase name"

# Case 5 (Edge): no XML files. Message "no JUnit XML", exit 1.
echo "# case 5: no JUnit XML files"
run bash "$sut" "$fix/none"
check_rc 1 "case 5: exit 1"
check_out 'no JUnit XML' "case 5: prints the no JUnit XML message"

# Case 6 (Edge): missing dir arg. Default dir "." is used.
echo "# case 6: default dir"
mkdir -p "$tmp/default"
cp "$fix/pass/TEST-first.xml" "$tmp/default/TEST-first.xml"
out=$(cd "$tmp/default" && bash "$sut" 2>&1)
rc=$?
check_rc 0 "case 6: exit 0 with no dir arg"
check_out 'tests=3( |$)' "case 6: reads TEST-*.xml from the current directory"

# Case 7 (Edge): nested dirs. All TEST-*.xml files are found.
echo "# case 7: nested directories"
run bash "$sut" "$fix/nested"
check_rc 0 "case 7: exit 0"
check_out 'files=2( |$)' "case 7: finds 2 files in nested dirs"
check_out 'tests=5( |$)' "case 7: sums tests to 5 across nested dirs"

# Case 8 (Edge): 0 tests in suite. Counted as 0, exit 0.
echo "# case 8: zero tests"
run bash "$sut" "$fix/zero"
check_rc 0 "case 8: exit 0"
check_out 'tests=0( |$)' "case 8: counts 0 tests"
check_out 'failures=0( |$)' "case 8: counts 0 failures"

echo
echo "# pass: $pass fail: $fail"
if [ "$fail" -ne 0 ]; then
    exit 1
fi
exit 0
