#!/usr/bin/env bash
# Installs the Three-Pass Review kit into a repository, or upgrades it.
#
# Usage: scripts/install.sh /path/to/your/repo [--upgrade | --force] [--light-reviewer addy|pr-review-toolkit]
#
#   (default)         Copy every kit file that isn't there yet. Existing files are left alone and listed.
#   --upgrade         Refresh the kit-owned files (workflows, scripts, reviewer instructions, checklists)
#                     to this version of the kit. Files your team edits are never touched:
#                     .github/review-policy.yml, CODEOWNERS, the PR template, .github/copilot-instructions.md
#                     and .github/instructions/. Use this to move a project to a newer kit.
#   --force           Overwrite everything, team-owned files included.
#   --light-reviewer  Pass 2's reviewer, written into a newly copied .github/review-policy.yml.
#
# It also vendors Addy Osmani's code-review-and-quality skill at a pinned commit,
# pins pass 3 to this kit's threepass commit, and prints the GitHub settings to change by hand.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kit_root="$(cd "$here/.." && pwd)"

target=""
mode="install"
reviewer=""
while [ $# -gt 0 ]; do
  case "$1" in
    --upgrade) mode="upgrade" ;;
    --force) mode="force" ;;
    --light-reviewer)
      reviewer="${2:-}"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *) target="$1" ;;
  esac
  shift
done
if [ -z "$target" ] || [ ! -d "$target" ]; then
  echo "Usage: $0 /path/to/your/repo [--upgrade | --force] [--light-reviewer addy|pr-review-toolkit]" >&2
  exit 1
fi
case "$reviewer" in
  "" | addy | pr-review-toolkit) ;;
  *)
    echo "--light-reviewer must be addy or pr-review-toolkit" >&2
    exit 1
    ;;
esac
target="$(cd "$target" && pwd)"

# Files a team edits for its own project. --upgrade never overwrites them.
team_owned() {
  case "$1" in
    .github/review-policy.yml | .github/CODEOWNERS | .github/pull_request_template.md | \
      .github/copilot-instructions.md | .github/instructions/*) return 0 ;;
  esac
  return 1
}

# GitHub uses the first CODEOWNERS / PR template it finds in .github/, the
# root or docs/. Adding ours next to an existing one would silently replace it.
existing_in_any() {
  local name="$1" dir
  for dir in "$target/.github" "$target" "$target/docs"; do
    [ -n "$(find "$dir" -maxdepth 1 -iname "$name" 2>/dev/null | head -n 1)" ] && return 0
  done
  return 1
}

# Stage the templates, with pass 3 pinned, so an upgrade compares like with like.
# Pass 3 runs threepass from this kit's own repository at this exact commit, so
# every project reviews with a known version until it upgrades.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$here/templates/." "$stage/"
if git -C "$kit_root" rev-parse --verify -q HEAD >/dev/null 2>&1; then
  sha="$(git -C "$kit_root" rev-parse HEAD)"
  repo="$(git -C "$kit_root" remote get-url origin 2>/dev/null | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')"
  repo="${repo:-lmagsino/three-pass-review}"
  deep="$stage/.github/workflows/deep-review.yml"
  sed -i.bak -E "s#^(  THREEPASS_REPO: ).*#\1$repo#; s#^(  THREEPASS_REF: ).*#\1$sha#" "$deep" && rm -f "$deep.bak"
  echo "Pass 3 pinned to $repo@${sha:0:12}."
  if [ -n "$(git -C "$kit_root" status --porcelain 2>/dev/null)" ]; then
    echo "  Note: this kit checkout has uncommitted changes, which the pinned commit doesn't include."
  fi
fi

copied=()
updated=()
skipped=()
while IFS= read -r -d '' src; do
  rel="${src#"$stage/"}"
  dest="$target/$rel"
  # A placeholder that the vendoring step replaces with the real skill.
  if [ "$rel" = ".claude/review/skills/code-review-and-quality/README.md" ] &&
     [ -f "$target/.claude/review/skills/code-review-and-quality/SKILL.md" ]; then
    continue
  fi
  base="$(basename "$rel")"
  exists=false
  if [ -e "$dest" ] ||
     { [ "$base" = "CODEOWNERS" ] && existing_in_any CODEOWNERS; } ||
     { [ "$base" = "pull_request_template.md" ] && existing_in_any pull_request_template.md; }; then
    exists=true
  fi
  if [ "$exists" = true ]; then
    if [ "$mode" = "force" ] || { [ "$mode" = "upgrade" ] && ! team_owned "$rel"; }; then
      if [ -e "$dest" ] && cmp -s "$src" "$dest"; then continue; fi
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      updated+=("$rel")
    else
      skipped+=("$rel")
    fi
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  copied+=("$rel")
done < <(find "$stage" -type f -print0 | sort -z)
chmod +x "$target/.github/scripts/"*.sh 2>/dev/null || true

policy="$target/.github/review-policy.yml"
if [ -n "$reviewer" ]; then
  if printf '%s\n' "${copied[@]:-}" "${updated[@]:-}" | grep -qx '.github/review-policy.yml'; then
    sed -i.bak -E "s#^(  reviewer: ).*#\1$reviewer#" "$policy" && rm -f "$policy.bak"
    echo "Pass 2 (light review) uses: $reviewer."
  else
    echo "Your .github/review-policy.yml was kept as it is. Set light_review.reviewer: $reviewer in it yourself."
  fi
fi

echo "Copied ${#copied[@]} new files into $target"
if [ "${#updated[@]}" -gt 0 ]; then
  echo "Updated ${#updated[@]} kit files:"
  printf '  %s\n' "${updated[@]}"
fi
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "Left these existing files alone (merge them by hand, or use --upgrade / --force):"
  printf '  %s\n' "${skipped[@]}"
fi
if [ -f "$policy" ] && ! grep -q '^light_review:' "$policy"; then
  echo
  echo "Your .github/review-policy.yml has no light_review section, so pass 2 uses Addy's skill."
  echo "To choose, add:"
  echo "  light_review:"
  echo "    reviewer: addy   # or pr-review-toolkit"
fi
echo

if [ -f "$target/.claude/review/skills/code-review-and-quality/SKILL.md" ] && [ "$mode" = "install" ]; then
  echo "Skill already vendored; skipping download."
else
  bash "$here/scripts/vendor-addy-skill.sh" "$target"
fi

if [ "$mode" = "upgrade" ]; then
  cat <<'EOF'

Upgraded. Review the changes with `git diff`, commit them on a branch, and open a PR.
Changes to the review setup always get a deep review.
EOF
  exit 0
fi

cat <<'EOF'

Next steps (see docs/setup.md for details):
  1. Edit .github/review-policy.yml and .github/CODEOWNERS: your sensitive paths and teams,
     and light_review.reviewer (addy or pr-review-toolkit).
     Edit the applyTo line in .github/instructions/sensitive-paths.instructions.md to match.
  2. Create the labels:      bash scripts/create-labels.sh owner/repo
  3. Add the secret:         gh secret set ANTHROPIC_API_KEY -R owner/repo
                             (used by pass 2, the light review, and pass 3, the deep review)
  4. Repository ruleset:     require a PR, 1 approval, review from Code Owners,
                             approval of the most recent push, and turn on
                             "Automatically request Copilot code review" (pass 1).
  5. Commit on a branch and open a PR. The tier check and the AI reviews only start
     working after this PR is merged (they read from the base branch), so have an
     eng lead review this one by hand with .github/review/deep-review-checklist.md.
  6. After merge, add `review-gate` as a required status check in the ruleset.

Later, to move this project to a newer kit: rerun this script with --upgrade.
EOF
