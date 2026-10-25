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

On Windows, native executables and trusted `.cmd`/`.bat` wrappers are supported.
Batch wrappers are launched with `cmd.exe`, independently of Vim's `shell`, with
AutoRun and delayed expansion disabled. Arguments are passed through a job-local
environment so spaces and shell metacharacters remain data. A wrapper must
forward `%*` without `CALL`, another `cmd /c`, delayed expansion, or reconstructing
arguments. Such additional parsing is outside this protection. Batch arguments
containing double quotes/control characters, or exceeding the safe command-line
length, are rejected with an error; native executable arguments are unchanged.

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

The CI also runs native Windows Vim, including `.cmd`/`.bat` forwarding tests
that compare a local recorder's actual arguments and check for command-injection
side effects. `test/command.vim` tests encoding and rejection on either platform;
`test/windows-command.vim` requires the recorder built by
`test/build-argv-recorder.ps1` (Windows PowerShell).

Tests create temporary Git repositories and a fake `gh` command. They do not
access GitHub or launch a browser. Failures are written to `test-errors.log`.

## License

[MIT](LICENSE)
