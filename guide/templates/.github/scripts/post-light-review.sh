#!/usr/bin/env bash
# Posts the light review (pass 2) as one sticky PR comment, and escalates the
# PR to deep review when the agent recommends it or reports Critical or
# Required findings. The agent never touches labels itself: this script does,
# from the agent's structured result, and it can only ever ADD the escalate
# label. The tier check (review-tier.yml) then moves the PR to deep.
#
# The comment's first line records which commit was reviewed and the result,
# e.g. <!-- light-review sha=abc123... result=clean -->. The tier check's merge
# gate reads it: a light PR passes only when the review is clean on its latest commit.
#
# Exits non-zero when the agent didn't finish, so the run shows as failed.
#
# Env:
#   GH_TOKEN, GITHUB_REPOSITORY   set by Actions
#   PR                            pull request number
#   HEAD_SHA                      the PR head commit that was reviewed
#   OUTCOME                       outcome of the agent step: success | failure
#   RESULT                        the agent's structured_output JSON (may be empty)
#   RUN_URL                       link to this workflow run
#   LABEL_ESCALATE                e.g. escalate/deep (must match review-policy.yml)
set -euo pipefail

body_file="$(mktemp)"
result="${RESULT:-}"
escalate=false
finished=false

if [ "${OUTCOME:-}" = "success" ] && [ -n "$result" ] && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$result"; then
  finished=true
  tier=$(jq -r '.recommended_tier // "deep"' <<<"$result")
  critical=$(jq -r '(.critical_count // 0) | floor' <<<"$result")
  required=$(jq -r '(.required_count // 0) | floor' <<<"$result")
  if [ "$tier" != "light" ] || [ "$critical" -gt 0 ] || [ "$required" -gt 0 ]; then
    escalate=true
  fi
  verdict=$([ "$escalate" = true ] && echo escalated || echo clean)
  {
    echo "<!-- light-review sha=$HEAD_SHA result=$verdict -->"
    jq -r '.summary_markdown // ""' <<<"$result"
    if [ "$escalate" = true ]; then
      echo
      echo "**Escalated to deep review** (label \`$LABEL_ESCALATE\`):"
      jq -r '(.escalation_reasons // []) | if length == 0 then ["Critical or Required findings above."] else . end | map("- " + .) | .[]' <<<"$result"
      echo
      echo "_Automation never removes this label. If it's wrong, a maintainer can remove it with a comment saying why._"
    fi
    echo
    echo "<sub>Reviewed commit ${HEAD_SHA:0:7}.</sub>"
  } >"$body_file"
else
  cat >"$body_file" <<EOF
<!-- light-review sha=$HEAD_SHA result=failed -->
### Light review (pass 2): didn't finish

The light review of commit ${HEAD_SHA:0:7} failed or returned no result ([run log](${RUN_URL:-#})). Until it completes, this PR can't take the light path. Re-run the **Light review** workflow, or add the \`$LABEL_ESCALATE\` label to review it as deep.
EOF
fi

# One sticky comment per PR: update ours if it exists, otherwise create it.
ids=$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PR/comments" \
  --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- light-review"))) | .id')
id="${ids%%$'\n'*}"
if [ -n "$id" ]; then
  gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" -F "body=@$body_file" >/dev/null
else
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$PR/comments" -F "body=@$body_file" >/dev/null
fi

if [ "$escalate" = true ]; then
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$PR/labels" -f "labels[]=$LABEL_ESCALATE" >/dev/null
  echo "Escalated PR #$PR to deep review."
elif [ "$finished" = true ]; then
  echo "Light review is clean; no escalation."
fi

if [ "$finished" != true ]; then
  echo "::error::The light review didn't finish. See the agent step's log." >&2
  exit 1
fi
