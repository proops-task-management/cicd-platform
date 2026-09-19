#!/usr/bin/env bash
# ===========================================================================
# check-action-pins.sh — the enforcer for IRD-015 §Rules (MIN-65).
#
# THE RULE. Every `uses:` reference must be exactly one of:
#   1. `./…`                                            a local action in this repo
#   2. `proops-task-management/cicd-platform/…@v6`      first-party, moving tag BY DESIGN
#   3. `owner/repo[/path]@<40-hex> # vX.Y.Z`            third-party, immutable + labelled
# Anything else fails: a third-party `@vN`, a branch ref, a bare SHA with no version
# comment, or a `docker://` image reference.
#
# WHY A SCRIPT AND NOT A SENTENCE IN AN IRD. MIN-58 put a pinning rule in a code
# comment; MIN-60 found a linter living in a local hook with no CI twin; MIN-62 found
# gitleaks with no CI counterpart; MIN-63 found the repo defining every gate running
# none on itself. Same defect every time: a safeguard living somewhere nothing forces
# it to run. Closing MIN-65 with prose would repeat that defect in the act of fixing
# it, so the rule gets an enforcer — and the enforcer runs in BOTH places.
#
# WHY GitHub'S OWN SHA-PINNING POLICY IS NOT USED (MIN-65 AC-8). That policy exempts
# reusable WORKFLOWS but not ACTIONS, and a reusable workflow's steps resolve under the
# CALLER's policy — so enabling it on the org or on a service repo would reject our own
# 21 first-party composite `@v6` references and end the moving-tag release model that
# IRD-015 is built on. Rule 2 above is precisely the exemption GitHub's policy cannot
# express, which is why enforcement lives here instead.
#
# WHY THE VERSION COMMENT IS MANDATORY, not decoration: Dependabot reads it. It bumps
# the SHA *and* rewrites the comment, so the upgrade signal survives pinning. A SHA with
# no comment is an un-updatable pin — secure and permanently stale.
#
# ONE FILE, THREE CALLERS: the `check-action-pins` composite action (self-ci here and
# iac-platform's action-pins.yml) and the pre-commit hook both exec THIS script, so
# local and CI cannot drift — lockstep is structural, not a pair of pins to remember.
#
# Usage: check-action-pins.sh [FILE ...]   (no args -> every tracked .github/**/*.y?ml)
#        Read-only, $0, no network. Exit 1 on any violation.
# ===========================================================================
set -euo pipefail

usage() {
  cat <<'EOF'
check-action-pins.sh [FILE ...]

Fails when a `uses:` reference is not one of:
  ./path/to/action                                     (local)
  proops-task-management/cicd-platform/...@v6          (first-party, moving tag by design)
  owner/repo@<40-char-sha> # vX.Y.Z                    (third-party, immutable + labelled)

  bad:   uses: actions/checkout@v7
  good:  uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

Find the SHA for a tag with:
  git ls-remote --tags https://github.com/<owner>/<repo>.git 'v7^{}'
(compare the PEELED `^{}` line — an annotated tag object is NOT the commit).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

files=("$@")
if [[ ${#files[@]} -eq 0 ]]; then
  while IFS= read -r f; do
    files+=("$f")
  done < <(git ls-files -- '.github/*.yml' '.github/*.yaml' '.github/**/*.yml' '.github/**/*.yaml')
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "check-action-pins: no workflow/action YAML to check"
  exit 0
fi

# A `uses:` key, with or without a leading sequence dash. Whole-line comments are skipped
# by the awk pass below: this repo's comments legitimately quote the BAD form while
# explaining it (see the header above), and the rule is about what Actions RESOLVES.
USES_KEY='[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*'

# TWO anchors for the SAME key, and the difference is load-bearing. The first grep runs on
# raw file lines; every grep AFTER it runs on `grep -n` output, where each line now starts
# with `<lineno>:`. Anchoring the allowed forms at plain `^` therefore matched NOTHING once
# numbering was added, so the -v filters removed nothing and the checker reported every line
# in the repo — including correctly pinned ones — as a violation.
# Caught by the POSITIVE test, not the negative one: a broken checker still fails bad input,
# so the negative test passed while the tool was useless. MIN-62's lesson, inverted — a red
# gate is evidence about the tree, not about the gate.
RAW_USES="^${USES_KEY}"
NUM_USES="^[0-9]+:${USES_KEY}"

# The three allowed forms, anchored so a trailing extra token cannot sneak through.
ALLOWED_LOCAL="${NUM_USES}\./[A-Za-z0-9._/-]+[[:space:]]*(#.*)?$"
ALLOWED_FIRST_PARTY="${NUM_USES}proops-task-management/cicd-platform/\.github/(workflows/[A-Za-z0-9._-]+\.ya?ml|actions/[A-Za-z0-9._-]+)@v6[[:space:]]*(#.*)?$"
ALLOWED_SHA_PINNED="${NUM_USES}[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(/[A-Za-z0-9._/-]+)?@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$"

rc=0
for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  # Blank whole-line comments rather than dropping them, so grep -n keeps real line numbers.
  if hits="$(awk '{ if ($0 ~ /^[[:space:]]*#/) print ""; else print }' "$f" \
             | LC_ALL=C grep -nE "$RAW_USES" \
             | LC_ALL=C grep -vE "$ALLOWED_LOCAL" \
             | LC_ALL=C grep -vE "$ALLOWED_FIRST_PARTY" \
             | LC_ALL=C grep -vE "$ALLOWED_SHA_PINNED")"; then
    while IFS= read -r hit; do
      printf '%s:%s\n' "$f" "$hit"
    done <<< "$hits"
    rc=1
  fi
done

if [[ "$rc" -ne 0 ]]; then
  cat >&2 <<'EOF'

check-action-pins: a `uses:` reference is not pinned to an immutable commit.

A tag is MUTABLE. The publisher — or anyone holding their credentials — can repoint it,
and every run then executes new code with NO diff in this repo. That is how
tj-actions/changed-files (CVE-2025-30066) and trivy-action (GHSA-69fq-xp46-6x23)
propagated. These pins run in jobs holding the gha-iac-apply AWS role and a GHCR
packages:write token.

Fix: uses: owner/repo@<40-char-sha> # vX.Y.Z
     git ls-remote --tags https://github.com/<owner>/<repo>.git 'vN^{}'   # PEELED line

First-party proops-task-management/cicd-platform/...@v6 refs are exempt: the moving tag
IS the release mechanism (IRD-015 §Rules). See MIN-65.
EOF
fi

exit "$rc"
