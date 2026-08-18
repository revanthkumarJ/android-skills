#!/bin/bash
# Sanitisation gate for docs extracted from a private codebase.
#
# These skills started life as internal documentation. Before publishing, every
# project-identifying term had to be stripped: product and company names, real
# package roots, class and file names, vendor SDKs, domain jargon.
#
# Fill in TERMS with the identifiers YOUR docs must never contain, then run this
# before every commit. It exits non-zero on a hit, so it works as a pre-commit
# hook or a CI step.
#
#   TERMS='AcmeCorp|acme|com\.acme|InternalWidget|\bWID\b'
#
# Use \b word boundaries for short or ambiguous tokens. Without them a
# three-letter internal acronym will match inside ordinary English words and
# bury you in false positives.
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE YOU FILL IN TERMS
#
# The moment you put real identifiers in TERMS, THIS FILE becomes the single
# most sensitive file in the repo: a tidy list of everything you are trying not
# to publish. It also has to exclude itself from its own scan, or it would
# always fail — so it cannot catch itself.
#
# Therefore: copy it, configure the copy, and never commit the copy.
#
#   cp leakcheck.sh leakcheck.local.sh
#   echo 'leakcheck.local.sh' >> .gitignore
#   # edit TERMS in leakcheck.local.sh, then gate every commit on it:
#   ./leakcheck.local.sh && git commit
#
# Three lessons, each learned the expensive way:
#   1. Scan EVERY file, not just *.md. An earlier version filtered to markdown
#      and was therefore blind to itself — the script's own term list, naming
#      every identifier being hidden, sailed through and got committed, and
#      pushed.
#   2. Run it as a gate BEFORE the commit, not as a report afterwards. A green
#      check printed after `git commit` has already lost.
#   3. Never let it print "clean" when it is unconfigured — see the guard below.
#      A verification tool that can pass without checking anything is worse than
#      no tool, because it manufactures confidence.
# ---------------------------------------------------------------------------

TERMS='REPLACE_ME_WITH_YOUR_IDENTIFIERS'

if [ "$TERMS" = "REPLACE_ME_WITH_YOUR_IDENTIFIERS" ]; then
    echo "leakcheck.sh is not configured — set TERMS to your identifiers first." >&2
    echo "Refusing to report 'clean' on an empty term list." >&2
    exit 2
fi

DST="$(cd "$(dirname "$0")" && pwd)"
SELF="$(basename "$0")"

hits=$(grep -rInE "$TERMS" "$DST" \
        --exclude-dir=.git \
        --exclude="$SELF" 2>/dev/null)

if [ -n "$hits" ]; then
    echo "LEAK DETECTED:"
    echo "$hits"
    exit 1
fi
echo "clean: no project-identifying terms found"
