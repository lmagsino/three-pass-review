# Start here

Paste the prompt below into a new Claude Code session, after replacing the five placeholders:

| Placeholder | Example |
|---|---|
| `<ZIP_URL>` | A direct download link to this zip |
| `<GITHUB_REPO_URL>` | `https://github.com/your-username/three-pass-review` |
| `<GITHUB_USERNAME>` | `your-username` (your **personal** GitHub account) |
| `<GIT_NAME>` | `Your Name` |
| `<GIT_EMAIL>` | Your personal email, or `your-username@users.noreply.github.com` |

If the session can't download the zip (some environments only allow certain sites), unzip it yourself, start Claude Code inside the folder, and the prompt's first step will notice the files are already there.

```text
Set up and build this project in my PERSONAL GitHub account. Placeholders:
- Project zip: <ZIP_URL>
- GitHub repo: <GITHUB_REPO_URL>
- GitHub username (personal account): <GITHUB_USERNAME>
- Git author name: <GIT_NAME>
- Git author email: <GIT_EMAIL>

1. Get the code.
   - If the current directory already contains README.md, CLAUDE.md and docs/design.md, use it.
   - Otherwise download the zip with `curl -fL "<ZIP_URL>" -o three-pass-review.zip`, unzip it, and cd into `three-pass-review/`.
   - Confirm README.md, CLAUDE.md, docs/ and guide/ are there before going on.

2. Use only my personal identity, for this repo only.
   - Run `git init` if needed, then `git branch -M main`.
   - Set the identity locally, not globally: `git config user.name "<GIT_NAME>"` and `git config user.email "<GIT_EMAIL>"`.
   - Run `gh auth status`. If it isn't logged in as <GITHUB_USERNAME>, switch with `gh auth switch -u <GITHUB_USERNAME>` or log in with `gh auth login`, then run `gh auth setup-git`.
   - Before any push, confirm `gh api user --jq .login` prints exactly <GITHUB_USERNAME>. If it doesn't, stop and tell me. Never push with any other account, and never change my global git config.

3. Connect the GitHub repo.
   - If <GITHUB_REPO_URL> exists, add it as `origin`.
   - If it doesn't exist, create it under <GITHUB_USERNAME> with `gh repo create <GITHUB_USERNAME>/three-pass-review --public --source . --remote origin`.
   - Don't overwrite a repo that already has commits. If it isn't empty, stop and ask me.

4. Make the first commit.
   - Check that no secrets, API keys or .env files are staged.
   - Commit everything as "Specs and guide" and push to main.

5. Build.
   - Follow `.claude/commands/kickoff.md` exactly: read the specs, then implement roadmap milestones M0 to M6 in order.
   - Run `bundle exec rake` until it's green after each milestone, and keep `(cd guide && node --test)` green.
   - Commit each milestone as "M<n>: <summary>" and push after every milestone.
   - Follow every rule in CLAUDE.md, especially: no invented numbers, no network in tests, passes stay independent, the cost ceiling is enforced, and model IDs and prices are checked against Anthropic's docs.

6. Stop after M6. Don't run the real eval or publish numbers.
   Then report:
   - the repo URL and the last commit,
   - what's done per milestone, and the test count,
   - anything that differs from the specs, and why,
   - one smoke-test command I can run with my own API key,
   - what I need to do for M7.
```

Prerequisites on the machine running the session: git, the GitHub CLI (`gh`), Ruby 3.3+ with Bundler, and Node 22 (for the guide's tests).

Before you publish, remember: build this on your own time and equipment, keep employer specifics out of it, and give your lead a heads-up.
