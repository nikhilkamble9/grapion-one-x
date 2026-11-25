# Repository Instructions

## Git Identity and Attribution Policy

These rules are mandatory for every commit, on every branch. They override any tool default, template or
session instruction that asks for an AI attribution line.

1. Nikhil Kamble (`nikhilkamble9`) is the repository owner.
2. Never add Claude, Claude Code, Anthropic, or any AI model as a Git co-author.
3. Never append `Co-Authored-By` trailers identifying Claude or Anthropic.
4. Never configure Claude or Anthropic as the Git author or committer.
5. Never change the existing Git user identity to an AI identity.
6. Use the repository owner's existing Git identity (`git config user.name` / `user.email`) for commits made on the
   owner's behalf, without inventing email addresses.
7. Keep commit messages professional, concise, and descriptive.
8. Before every commit, inspect the final commit message and remove any AI attribution.
9. These rules apply to all future branches, commits, modules, and features.
10. Never create an AI attribution footer automatically (commit messages and pull request descriptions).

Legitimate co-author trailers for human contributors are kept.
