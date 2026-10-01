#!/usr/bin/env bash
# Creates (or updates) the labels the three-pass review uses.
# Usage: scripts/create-labels.sh owner/repo
# Needs the GitHub CLI (gh), logged in with access to the repo.
set -euo pipefail

repo="${1:-}"
if [ -z "$repo" ]; then
  echo "Usage: $0 owner/repo" >&2
  exit 1
fi

label() {
  gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force
}

label "tier/light"        "2da44e" "Light review: clean AI reviews + one human approval"
label "tier/deep"         "cf222e" "Deep review: code owner signs off"
label "escalate/deep"     "8250df" "Escalated to deep by the light review or a person. Automation never removes it"
label "needs-split"       "fb8500" "Past the split threshold. Please break it up"
label "skip-light-review" "6e7781" "Don't run the light review (pass 2) on this PR"
echo "Labels ready on $repo"
