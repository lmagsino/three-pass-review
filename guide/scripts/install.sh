#!/usr/bin/env bash
# Copies the three-pass review kit into your repository.
#
# Usage: scripts/install.sh /path/to/your/repo [--force]
#
# - Copies everything under templates/ into the repo. Existing files are left
#   alone (and listed) unless you pass --force.
# - Vendors Addy Osmani's code-review-and-quality skill at a pinned commit.
# - Prints the GitHub settings you still need to change by hand.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"
force="${2:-}"
if [ -z "$target" ] || [ ! -d "$target" ]; then
  echo "Usage: $0 /path/to/your/repo [--force]" >&2
  exit 1
fi
target="$(cd "$target" && pwd)"

# GitHub uses the first CODEOWNERS / PR template it finds in .github/, the
# root or docs/. Adding ours next to an existing one would silently replace it.
existing_in_any() {
  local name="$1" dir
  for dir in "$target/.github" "$target" "$target/docs"; do
    [ -n "$(find "$dir" -maxdepth 1 -iname "$name" 2>/dev/null | head -n 1)" ] && return 0
  done
  return 1
}

copied=0
skipped=()
while IFS= read -r -d '' src; do
  rel="${src#"$here/templates/"}"
  dest="$target/$rel"
  base="$(basename "$rel")"
  if [ "$force" != "--force" ]; then
    if [ -e "$dest" ] ||
       { [ "$base" = "CODEOWNERS" ] && existing_in_any CODEOWNERS; } ||
       { [ "$base" = "pull_request_template.md" ] && existing_in_any pull_request_template.md; }; then
      skipped+=("$rel")
      continue
    fi
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  copied=$((copied + 1))
done < <(find "$here/templates" -type f -print0)
chmod +x "$target/.github/scripts/post-light-review.sh" 2>/dev/null || true

echo "Copied $copied files into $target"
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "Left these existing files alone (merge them by hand, or rerun with --force):"
  printf '  %s\n' "${skipped[@]}"
fi
echo

if [ -f "$target/.claude/review/skills/code-review-and-quality/SKILL.md" ] && [ "$force" != "--force" ]; then
  echo "Skill already vendored; skipping download."
else
  bash "$here/scripts/vendor-addy-skill.sh" "$target"
fi

cat <<'EOF'

Next steps (see docs/setup.md for details):
  1. Edit .github/review-policy.yml and .github/CODEOWNERS: your sensitive paths and teams.
     Edit the applyTo line in .github/instructions/sensitive-paths.instructions.md to match.
  2. Create the labels:      bash scripts/create-labels.sh owner/repo
  3. Add the secret:         gh secret set ANTHROPIC_API_KEY -R owner/repo
  4. Repository ruleset:     require a PR, 1 approval, review from Code Owners,
                             approval of the most recent push, and turn on
                             "Automatically request Copilot code review".
  5. Commit on a branch and open a PR. The tier check and light review only start
     working after this PR is merged (they read from the base branch), so have an
     eng lead review this one by hand with .github/review/deep-review-checklist.md.
  6. After merge, add `review-gate` as a required status check in the ruleset.
EOF
