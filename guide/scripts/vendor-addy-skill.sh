#!/usr/bin/env bash
# Copies a pinned version of Addy Osmani's code-review-and-quality skill
# (MIT, https://github.com/addyosmani/agent-skills) into .claude/review/ in
# your repo, where the light review (pass 2) reads it.
#
# It goes in .claude/review/skills/, not .claude/skills/, on purpose: Copilot
# and Claude Code auto-load skills from .claude/skills/, and pass 1 (Copilot)
# should stay a different reviewer from pass 2.
#
# Usage: scripts/vendor-addy-skill.sh /path/to/your/repo [commit-sha]
#
# Update on purpose: rerun with a newer commit SHA, read the diff, and open a
# PR. That PR touches .claude/, so it gets a deep review.
set -euo pipefail

DEFAULT_SHA="2686b620fc1fed2e8f60c704839c766b8594c6b6"   # main as of 2026-10-01

target="${1:-}"
sha="${2:-$DEFAULT_SHA}"
if [ -z "$target" ] || [ ! -d "$target" ]; then
  echo "Usage: $0 /path/to/your/repo [commit-sha]" >&2
  exit 1
fi

raw="https://raw.githubusercontent.com/addyosmani/agent-skills/$sha"
review_dir="$target/.claude/review"
skill_dir="$review_dir/skills/code-review-and-quality"
ref_dir="$review_dir/references"
mkdir -p "$skill_dir" "$ref_dir"

fetch() {
  local url="$1" out="$2"
  if ! curl -fsSL --retry 2 -o "$out" "$url"; then
    echo "Could not download $url" >&2
    exit 1
  fi
  echo "  wrote ${out#"$target"/}"
}

echo "Vendoring addyosmani/agent-skills @ ${sha:0:12} into $target"
fetch "$raw/skills/code-review-and-quality/SKILL.md" "$skill_dir/SKILL.md"
# The skill links to these as ../../references/*.md
fetch "$raw/references/security-checklist.md" "$ref_dir/security-checklist.md"
fetch "$raw/references/performance-checklist.md" "$ref_dir/performance-checklist.md"

license="$(mktemp)"
curl -fsSL --retry 2 -o "$license" "$raw/LICENSE"
{
  echo "# Third-party notices"
  echo
  echo "These files are copied unmodified from addyosmani/agent-skills at commit \`$sha\`:"
  echo
  echo "- \`.claude/review/skills/code-review-and-quality/SKILL.md\`"
  echo "- \`.claude/review/references/security-checklist.md\`"
  echo "- \`.claude/review/references/performance-checklist.md\`"
  echo
  echo "Source: https://github.com/addyosmani/agent-skills/tree/$sha"
  echo
  echo '```'
  cat "$license"
  echo '```'
} >"$review_dir/THIRD_PARTY_NOTICES.md"
rm -f "$license"
echo "  wrote .claude/review/THIRD_PARTY_NOTICES.md"

head -n 5 "$skill_dir/SKILL.md" | grep -q '^name: code-review-and-quality' || {
  echo "Downloaded SKILL.md doesn't look like the code-review-and-quality skill. Check the commit SHA." >&2
  exit 1
}
rm -f "$skill_dir/README.md"
echo "Done."
