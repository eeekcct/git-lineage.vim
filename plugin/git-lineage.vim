vim9script

highlight default link GitLineagePopup Normal
highlight default link GitLineageBorder Comment

def Show()
  if !executable('git')
    echoerr 'git command not found'
    return
  endif

  var file = expand('%:p')
  var lnum = line('.')

  if empty(file)
    echoerr 'No File'
    return 
  endif

  var dir = fnamemodify(file, ':h')
  var git = 'git -C ' .. shellescape(dir)

  var repo_check = system(git .. ' rev-parse --is-inside-work-tree')

  if v:shell_error != 0 || trim(repo_check) != 'true'
    echoerr 'Not inside a Git repository'
    return
  endif

  var filename = fnamemodify(file, ':t')

  var sha_cmd = git
    .. ' blame -L ' .. lnum .. ',' .. lnum
    .. ' --porcelain -- ' .. shellescape(filename)
  var sha_output = systemlist(sha_cmd)

  if v:shell_error != 0 || empty(sha_output)
    echoerr 'git blame failed'
    return
  endif

  var sha = split(sha_output[0])[0]

  if sha =~ '^0\+$'
    echoerr 'Current line is not committed yet'
    return
  endif

  var commit_cmd = git .. ' show -s --format="%h%x09%an%x09%ad%x09%s" --date=short ' .. shellescape(sha)
  var commit_output = trim(system(commit_cmd))

  if v:shell_error != 0 || empty(commit_output)
    echoerr 'git show failed'
    return
  endif

  var fields = split(commit_output, "\t")

  if len(fields) != 4
    echoerr 'Invalid commit info'
    return
  endif

  var lines = [
    'Commit: ' .. fields[0],
    'Author: ' .. fields[1],
    'Date:   ' .. fields[2],
    'Title:  ' .. fields[3],
  ]

  var repo_info = GetRepoInfo(git)

  var host = ''
  var repo = ''

  if len(repo_info) == 2
    host = repo_info[0]
    repo = repo_info[1]
  endif

  var pr_number = AddPrInfo(lines, sha, host, repo)

  popup_create(lines, {
    'title': ' Git Lineage ',
    'border': [],
    'padding': [0, 1, 0, 1],
    'highlight': 'GitLineagePopup',
    'borderhighlight': ['GitLineageBorder'],
    'close': 'click',
    'filter': (id, key) => PopupFilter(id, key, host, repo, pr_number),
  })
enddef

def PopupFilter(id: number, key: string, host: string, repo: string, pr_number: string): bool
  if key == 'q' || key == "\<Esc>"
    popup_close(id)
    return true
  endif 

  if key == 'o' && !empty(host) && !empty(repo) && !empty(pr_number)
    system(
      'gh pr view '
      .. shellescape(pr_number)
      .. ' --repo ' .. shellescape(host .. '/' .. repo)
      .. ' --web'
    )
    return true
  endif

  return false
enddef

def GetRemoteName(git: string): string
  var upstream = trim(system(
    git .. ' rev-parse --abbrev-ref --symbolic-full-name ' .. shellescape('@{u}')
  ))

  if v:shell_error == 0 && !empty(upstream)
    return split(upstream, '/')[0]
  endif

  var remotes = systemlist(git .. ' remote')
  
  if index(remotes, 'origin') >= 0
    return 'origin'
  endif

  return ''
enddef

def GetRepoInfo(git: string): list<string>
  var remote_name = GetRemoteName(git)
  if empty(remote_name)
    return []
  endif

  var remote = trim(system(
    git .. ' remote get-url ' .. shellescape(remote_name)
  ))

  if v:shell_error != 0 || empty(remote)
    return []
  endif

  remote = substitute(remote, '\.git$', '', '')

  var ssh_match = matchlist(remote, '^git@\([^:]\+\):\(.\+\)$')

  if !empty(ssh_match)
    return [ssh_match[1], ssh_match[2]]
  endif

  var https_match = matchlist(remote, '^https://\([^/]\+\)/\(.\+\)$')

  if !empty(https_match)
    return [https_match[1], https_match[2]]
  endif

  return []
enddef

def AddPrInfo(lines: list<string>, sha: string, host: string, repo: string): string
  if !executable('gh')
    add(lines, '')
    add(lines, 'gh command not found')
    return ''
  endif

  if empty(host) || empty(repo)
    return ''
  endif

  var endpoint = 'repos/' .. repo .. '/commits/' .. sha .. '/pulls'
  var cmd = 'gh api'
    .. ' --hostname ' .. shellescape(host)
    .. ' ' .. shellescape(endpoint)
    .. ' --jq '
    .. shellescape('.[0] | [.number, .title, .html_url] | @tsv')

  var output = trim(system(cmd))

  if v:shell_error != 0
    add(lines, '')
    add(lines, 'GitHub API error')
    add(lines, 'Check gh authentication or API access for ' .. host)
    return ''
  endif

  if empty(output)
    return ''
  endif

  var pr = split(output, "\t")

  if len(pr) != 3
    return ''
  endif

  add(lines, '')
  add(lines, 'PR #' .. pr[0])
  add(lines, 'Title: ' .. pr[1])
  add(lines, 'URL:   ' .. pr[2])

  return pr[0]
enddef

command! GitLineage Show()
