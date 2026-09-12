# Contributing

Use a topic branch and submit a pull request against `main`. Describe the
problem, the resulting behavior, and how you verified the change.

- Keep the entry point in `plugin/` small; implementation belongs in `autoload/`.
- Use Vim9 script for implementation, two spaces for indentation, and LF endings.
- Keep `README.md` and `doc/git-lineage.txt` in sync when behavior changes.
- Add regression coverage for bug fixes. Tests should use temporary fixtures
  and avoid real GitHub requests or browser launches.
- Do not commit generated `doc/tags` or test logs.

Run from the repository root before opening a PR:

```sh
vim -Nu NONE -i NONE -n -es -S test/run.vim
git diff --check
```

The test runner requires Vim with `+vim9script` and `+popupwin`, and Git.
Failures are recorded in `test-errors.log` and produce a nonzero exit code.

For a manual check, load the plugin in Vim, open a tracked file, and run
`:GitLineage`. Check the popup, `q`/`Esc`, and `o` with a GitHub commit that has
an associated PR. Also try an unsaved insertion above the target line.
