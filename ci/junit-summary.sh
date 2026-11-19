#!/usr/bin/env bash
# Print a JUnit summary for Woodpecker CI.
#
# Read every TEST-*.xml file under a directory (default: .).
# Sum the tests, failures, errors and skipped attributes of the
# <testsuite> elements. Print the totals and the name of each failing
# testcase.
#
# Usage: bash ci/junit-summary.sh [dir]
# Needs only grep, sed, awk and find.
#
# Exit 0 when there is no failure and no error.
# Exit 1 when a failure or an error exists, or when no XML file exists.

set -u

dir="${1:-.}"

if [ ! -d "$dir" ]; then
    echo "no JUnit XML: not a directory: $dir" >&2
    exit 1
fi

files=$(find "$dir" -type f -name 'TEST-*.xml' | sort)

if [ -z "$files" ]; then
    echo "no JUnit XML files found in $dir" >&2
    exit 1
fi

nfiles=$(printf '%s\n' "$files" | awk 'END { print NR }')

# Join a start tag that spans more than one line, then put each tag on its
# own line. One tag per line makes the awk rules below simple.
printf '%s\n' "$files" |
    while IFS= read -r file; do
        sed ':a; /<[^>]*$/ { N; s/\n[[:space:]]*/ /; ba; }' "$file" |
            awk '{ gsub(/>/, ">\n"); print }'
    done |
    awk -v nfiles="$nfiles" -v dir="$dir" '
# Read one numeric attribute from a start tag. Return 0 when it is absent.
function attr(tag, key,   pat, digits) {
    pat = "[ \t]" key "=\"[0-9]+\""
    if (!match(tag, pat)) {
        return 0
    }
    digits = RLENGTH - length(key) - 4
    return substr(tag, RSTART + length(key) + 3, digits) + 0
}

function show_bad_case() {
    if (tclass != "") {
        printf "FAILED: %s.%s\n", tclass, tname
    } else {
        printf "FAILED: %s\n", tname
    }
}

BEGIN {
    tests = 0
    failures = 0
    errors = 0
    skipped = 0
    suites = 0
    intest = 0
    bad = 0
    tname = ""
    tclass = ""
}

/<testsuite[ \t>]/ {
    tests    += attr($0, "tests")
    failures += attr($0, "failures")
    errors   += attr($0, "errors")
    skipped  += attr($0, "skipped")
    suites++
    next
}

/<testcase[ \t>]/ {
    intest = 1
    bad = 0
    tname = ""
    tclass = ""
    if (match($0, /[ \t]name="[^"]*"/)) {
        tname = substr($0, RSTART + 7, RLENGTH - 8)
    }
    if (match($0, /[ \t]classname="[^"]*"/)) {
        tclass = substr($0, RSTART + 12, RLENGTH - 13)
    }
    # A self-closing testcase has no child element.
    if ($0 ~ /\/>[ \t]*$/) {
        intest = 0
    }
    next
}

intest == 1 && /<(failure|error)[ \t\/>]/ {
    bad = 1
}

intest == 1 && /<\/testcase>/ {
    if (bad == 1) {
        show_bad_case()
    }
    intest = 0
}

END {
    printf "JUnit summary for %s: files=%d suites=%d tests=%d failures=%d errors=%d skipped=%d\n", \
        dir, nfiles, suites, tests, failures, errors, skipped
    if (failures + errors > 0) {
        exit 1
    }
    exit 0
}
'

rc=$?
exit "$rc"
