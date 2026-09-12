vim9script

var popup_id = 0

export def Show()
  if popup_id != 0
    popup_close(popup_id)
    popup_id = 0
  endif

  if !executable('git')
    echoerr 'git-lineage: git command not found'
    return
  endif

  var file = expand('%:p')
  if empty(file) || &buftype != ''
    echoerr 'git-lineage: Open a file first'
    return
  endif

  var git = 'git --literal-pathspecs -C ' .. shellescape(fnamemodify(file, ':h'))
  var repo_check = system(git .. ' rev-parse --is-inside-work-tree')
  if v:shell_error != 0 || trim(repo_check) != 'true'
    echoerr 'git-lineage: Not inside a Git repository'
    return
  endif

  var lnum = line('.')
  var blame_cmd = git .. ' blame --porcelain -L ' .. lnum .. ',' .. lnum
    .. ' -- ' .. shellescape(fnamemodify(file, ':t'))
  var blame = systemlist(blame_cmd)
  if v:shell_error != 0 || empty(blame)
    echoerr 'git-lineage: git blame failed; the file must be tracked with committed history'
    return
  endif

  var sha = split(blame[0])[0]
  if sha =~ '^0\+$'
    echoerr 'git-lineage: Current line is not committed yet'
    return
  endif

  # Newline separators preserve tabs and empty subjects in commit messages.
  var fields = systemlist(git .. ' show -s --format='
    .. shellescape('%h%n%an%n%ad%n%s') .. ' --date=short ' .. shellescape(sha))
  if v:shell_error != 0 || len(fields) < 3
    echoerr 'git-lineage: git show failed'
    return
  endif
  var lines = [
    'Commit: ' .. fields[0],
    'Author: ' .. fields[1],
    'Date:   ' .. fields[2],
    'Title:  ' .. join(fields[3 :], ' '),
  ]

  var repo_info = GetRepoInfo(git)
  var host = get(repo_info, 0, '')
  var repo = get(repo_info, 1, '')
  var pr_number = AddPrInfo(lines, sha, host, repo)
  add(lines, '')
  add(lines, empty(pr_number) ? 'q/Esc: close' : 'o: open PR | q/Esc: close')

  popup_id = popup_atcursor(lines, {
    'pos': 'botleft',
    'line': 'cursor-1',
    'col': 'cursor+10',
    'title': ' Git Lineage ',
    'border': [],
    'padding': [0, 1, 0, 1],
    'highlight': 'GitLineagePopup',
    'borderhighlight': ['GitLineageBorder'],
    'close': 'click',
    'moved': 'any',
    'filtermode': 'n',
    'filter': (id, key) => PopupFilter(id, key, host, repo, pr_number),
  })
enddef

def PopupFilter(id: number, key: string, host: string, repo: string, pr_number: string): bool
  if key == 'q' || key == "\<Esc>"
    popup_close(id)
    return true
  endif

  if key == 'o'
    if !empty(pr_number)
      system('gh pr view ' .. shellescape(pr_number)
        .. ' --repo ' .. shellescape(host .. '/' .. repo) .. ' --web')
      if v:shell_error != 0
        echohl WarningMsg
        echomsg 'git-lineage: Could not open the PR; check gh authentication and browser settings'
        echohl None
      endif
    endif
    return true
  endif
  return false
enddef

def GetRemoteName(git: string): string
  var branch = trim(system(git .. ' symbolic-ref --quiet --short HEAD'))
  if v:shell_error == 0 && !empty(branch)
    var remote = trim(system(git .. ' config --get ' .. shellescape('branch.' .. branch .. '.remote')))
    if v:shell_error == 0 && !empty(remote) && remote != '.'
      return remote
    endif
  endif

  var remotes = systemlist(git .. ' remote')
  return index(remotes, 'origin') >= 0 ? 'origin' : ''
enddef

def GetRepoInfo(git: string): list<string>
  var remote_name = GetRemoteName(git)
  if empty(remote_name)
    return []
  endif

  var remote = trim(system(git .. ' remote get-url ' .. shellescape(remote_name)))
  if v:shell_error != 0 || empty(remote)
    return []
  endif
  remote = substitute(remote, '/\+$', '', '')
  remote = substitute(remote, '\.git$', '', '')

  var matched = matchlist(remote, '^git@\([^/:]\+\):\([^/]\+/[^/]\+\)$')
  if empty(matched)
    matched = matchlist(remote, '^https://\([^/@:]\+\)/\([^/]\+/[^/]\+\)$')
  endif
  if empty(matched)
    matched = matchlist(remote, '^ssh://git@\([^/:]\+\)\%(:[0-9]\+\)\?/\([^/]\+/[^/]\+\)$')
  endif
  return empty(matched) ? [] : [matched[1], matched[2]]
enddef

def AddPrInfo(lines: list<string>, sha: string, host: string, repo: string): string
  if empty(host) || empty(repo)
    return ''
  endif
  add(lines, '')
  if !executable('gh')
    add(lines, 'Install gh to show pull request information')
    return ''
  endif

  var endpoint = 'repos/' .. repo .. '/commits/' .. sha .. '/pulls'
  var output = trim(system('gh api --hostname ' .. shellescape(host)
    .. ' ' .. shellescape(endpoint) .. ' --jq ' .. shellescape('.[0] // {}')))
  if v:shell_error != 0
    add(lines, 'GitHub API error')
    add(lines, 'Check gh authentication or API access for ' .. host)
    return ''
  endif

  var pr: dict<any>
  try
    pr = json_decode(output)
  catch
    add(lines, 'Invalid GitHub API response')
    return ''
  endtry
  if empty(pr)
    add(lines, 'No pull request found')
    return ''
  endif
  if type(get(pr, 'number', '')) != v:t_number || get(pr, 'number', 0) <= 0
      || type(get(pr, 'title', 0)) != v:t_string || type(get(pr, 'html_url', 0)) != v:t_string
    add(lines, 'Invalid GitHub API response')
    return ''
  endif

  add(lines, 'PR #' .. pr.number)
  add(lines, 'Title: ' .. substitute(pr.title, '[\r\n\t]', ' ', 'g'))
  add(lines, 'URL:   ' .. pr.html_url)
  return string(pr.number)
enddef
