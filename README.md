# git-lineage.vim

See the commit behind the line under your cursor, then open its GitHub pull
request without leaving Vim to search for it.

Run `:GitLineage` to show a popup with the commit hash, author, date, subject,
and associated pull request when available.

## Requirements

- Vim 9.0 or later with `+vim9script` and `+popupwin` (Neovim is not supported).
- `git` on your `PATH`.
- Optional: [GitHub CLI (`gh`)](https://cli.github.com/) on your `PATH`,
  to look up and open pull requests.

Commit information works without `gh`.

Authentication is handled by `gh`. See `:help git-lineage-requirements`
for details.

## Installation

With Vim's built-in packages, clone into a `pack/*/start/` directory:

```sh
git clone git@github.com:eeekcct/git-lineage.vim.git ~/.vim/pack/plugins/start/git-lineage.vim
```

On Windows, use `~/vimfiles/pack/plugins/start/git-lineage.vim` instead.
Restart Vim, then run `:helptags ALL` to make `:help git-lineage` available.

Or add `eeekcct/git-lineage.vim` using your preferred plugin manager.

## Usage

Open a tracked file, place the cursor on a committed line, and run:

```vim
:GitLineage
```

While the popup is visible in Normal mode:

| Key | Action |
| --- | --- |
| `o` | Open the displayed PR in your browser, if one was found |
| `q` / `Esc` | Close the popup |

The popup also closes when the cursor moves or when you click inside it.
Running the command again replaces the previous popup.

No default key binding is installed. An optional mapping for your vimrc:

```vim
nmap <silent> <Leader>gl <Plug>(git-lineage)
```

## Behavior and limitations

- Blame uses the current buffer, including unsaved edits. Newly added or changed
  lines without a commit report `Current line is not committed yet`.
- Files need committed Git history. Untracked files and special buffers are
  not supported.
- PR lookup uses the current branch's configured remote, falling back to
  `origin` when there is no remote configured or HEAD is detached.
- Supported remote URL forms are `git@HOST:OWNER/REPO.git`,
  `https://HOST/OWNER/REPO.git`, and `ssh://git@HOST[:PORT]/OWNER/REPO.git`.
  The host must provide the GitHub API for PR lookup.
- If GitHub returns several PRs for a commit, the first result is displayed.
  A commit without an associated PR still shows its commit information.
- Git and GitHub CLI commands run synchronously. Large histories or a slow
  network can delay the popup.

The popup uses the `GitLineagePopup` and `GitLineageBorder` highlight groups,
linked to `Normal` and `Comment` by default. See `:help git-lineage` for details.

## Development

Run the regression tests from the repository root:

```sh
vim -Nu NONE -i NONE -n -es -S test/run.vim
```

Tests create temporary Git repositories and a fake `gh` command. They do not
access GitHub or launch a browser. Failures are written to `test-errors.log`.
See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## License

[MIT](LICENSE)
