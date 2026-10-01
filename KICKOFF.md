# Kickoff: build threepass with Claude Code

The specs are written. These steps get a new Claude Code session to build milestones M0 to M6 from them.

**Setting up a new GitHub repo too?** Use [START_HERE.md](START_HERE.md) instead. It downloads the zip, pushes to your personal GitHub account, and then runs this same build.

1. Unzip this folder and open a terminal in it.
2. Start Claude Code in the folder: `claude`
3. Run the project command:

   ```
   /kickoff
   ```

   The command's full text is in [`.claude/commands/kickoff.md`](.claude/commands/kickoff.md). If your Claude surface doesn't load project commands, paste that file's text (everything below the `---` header) as your first message instead.

The session reads `CLAUDE.md` automatically. It builds milestone by milestone, commits after each one, and stops after M6 to hand back to you. It won't spend money on a real eval run or publish numbers.

**Before you start:**
- Install Ruby 3.3+ and Bundler.
- Have an Anthropic API key ready for the one smoke test at the end. Tests never call the API.
- Build this on your own time and equipment, keep employer specifics out of it, and give your lead a heads-up before publishing.
