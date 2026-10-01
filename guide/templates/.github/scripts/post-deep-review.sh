#!/usr/bin/env bash
# Posts pass 3, the deep review, as one sticky PR comment, updated for each
# new head commit. The last line records the commit it covers,
# <!-- threepass-sha=... -->, so the tier check doesn't start pass 3 twice for
# one commit.
#
# threepass exit codes: 0 ran, 3 refused by the cost ceiling (its output says
# why), 1 error. Pass 3 never blocks a merge, so only an error fails this job.
#
# Env:
#   GH_TOKEN, GITHUB_REPOSITORY, RUNNER_TEMP   set by Actions
#   PR, HEAD_SHA, EXIT_CODE, RUN_URL           set by deep-review.yml
set -euo pipefail

report="$RUNNER_TEMP/report.md"
body_file="$(mktemp)"
code="${EXIT_CODE:-1}"

if [ "$code" = 0 ] || [ "$code" = 3 ]; then
  cat "$report" >"$body_file"
else
  {
    echo "<!-- threepass -->"
    echo "### Deep review (pass 3): didn't finish"
    echo
    echo "\`threepass\` failed on commit ${HEAD_SHA:0:7} ([run log](${RUN_URL:-#})). The usual causes are a missing" \
      "\`ANTHROPIC_API_KEY\` secret, or no pricing for the model set in \`.threepass.yml\`. The deep reviewers can" \
      "start from the light review and the deep review checklist. To try again, run the **Deep review** workflow" \
      "with this PR's number and **force** on."
  } >"$body_file"
fi
{
  echo
  echo "<sub>Pass 3 (deep review) of commit ${HEAD_SHA:0:7}. It informs the deep reviewers; it doesn't approve or block.</sub>"
  echo "<!-- threepass-sha=$HEAD_SHA -->"
} >>"$body_file"

ids=$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PR/comments" \
  --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- threepass"))) | .id')
id="${ids%%$'\n'*}"
if [ -n "$id" ]; then
  gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" -F "body=@$body_file" >/dev/null
else
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$PR/comments" -F "body=@$body_file" >/dev/null
fi
echo "Posted the deep review for ${HEAD_SHA:0:7}."

if [ "$code" != 0 ] && [ "$code" != 3 ]; then
  echo "::error::threepass didn't finish (exit $code). See the Run threepass step." >&2
  exit 1
fi
