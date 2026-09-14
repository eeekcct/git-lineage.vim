# git-lineage.vim

See the commit behind the line under your cursor, then open its GitHub pull
request without leaving Vim to search for it.

Run `:GitLineage` to show a popup with the commit hash, author, date, and
subject. Git and GitHub lookups run in the background, and pull request
details can be loaded from the popup when needed.

## Requirements

- Vim 9.0 or later with `+vim9script`, `+popupwin`, and `+job`
  (Neovim is not supported).
- [Git](https://git-scm.com/) on your `PATH`.
- Optional: [GitHub CLI (`gh`)](https://cli.github.com/) on your `PATH`,
  to look up and open pull requests or open commits on GitHub.

Commit information works without `gh`.

Authentication is handled by `gh`. See `:help git-lineage-requirements`
for details.

## Installation

With Vim's built-in packages, clone into a `pack/*/start/` directory:

```sh
git clone https://github.com/eeekcct/git-lineage.vim.git ~/.vim/pack/plugins/start/git-lineage.vim
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
| `p` | Look up and display the associated PR |
| `o` | Look up the associated PR and open it without changing the popup |
| `c` | Open the commit in your browser |
| `q` / `Esc` | Close the popup |

The popup also closes when the cursor moves or when you click inside it.
Running the command again replaces the previous popup.
It opens above the cursor, with its left edge offset 10 screen columns to the
right; Vim adjusts the position when it would go outside the screen.

No default key binding is installed. An optional mapping for your vimrc:

```vim
nmap <silent> <Leader>gl <Plug>(git-lineage)
```

PR lookup is disabled on initial display by default. To include PR details
whenever the popup opens, add this to your vimrc:

```vim
let g:git_lineage_show_pr = 1
```

## Behavior and limitations

- Blame uses the saved file on disk. Save the file before running the command;
  unsaved insertions or deletions can make the cursor line refer to a different
  saved line. Newly added or changed lines without a commit report
  `Current line is not committed yet`.
- Files need committed Git history. Untracked files and special buffers are
  not supported.
- PR lookup uses the current branch's configured remote, falling back to
  `origin` when there is no remote configured or HEAD is detached.
- Supported remote URL forms are `git@HOST:OWNER/REPO.git`,
  `https://HOST/OWNER/REPO.git`, and `ssh://git@HOST[:PORT]/OWNER/REPO.git`.
  The host must provide the GitHub API for PR lookup.
- If GitHub returns several PRs for a commit, the first result is displayed.
  A commit without an associated PR still shows its commit information.
- Git commands, GitHub API requests, and browser commands run in the
  background. The popup shows a loading message while a lookup is in progress.
  Closing the popup cancels its unfinished Git and GitHub API jobs. A PR lookup
  is reused while the popup remains open; no persistent cache is maintained.

The popup uses the `GitLineagePopup` and `GitLineageBorder` highlight groups,
linked to `Normal` and `Comment` by default. See `:help git-lineage` for details.

## Development

Run the regression tests from the repository root:

```sh
vim -Nu NONE -i NONE -n -es -S test/run.vim
```

Tests create temporary Git repositories and a fake `gh` command. They do not
access GitHub or launch a browser. Failures are written to `test-errors.log`.

## License

[MIT](LICENSE)
