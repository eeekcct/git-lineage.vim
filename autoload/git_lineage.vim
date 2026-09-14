vim9script

var popup_id = 0
var browser_jobs: list<job> = []

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
  var lnum = line('.')
  var blame_cmd = git .. ' blame --porcelain -L ' .. lnum .. ',' .. lnum
    .. ' -- ' .. shellescape(fnamemodify(file, ':t'))
  var blame = systemlist(blame_cmd)
  if v:shell_error != 0 || empty(blame)
    var repo_check = system(git .. ' rev-parse --is-inside-work-tree')
    if v:shell_error != 0 || trim(repo_check) != 'true'
      echoerr 'git-lineage: Not inside a Git repository'
      return
    endif
    echoerr 'git-lineage: git blame failed; the file must be tracked with committed history'
    return
  endif

  var sha = split(blame[0])[0]
  if sha =~ '^0\+$'
    echoerr 'git-lineage: Current line is not committed yet'
    return
  endif

  var commit = ParseBlame(blame, sha)
  if empty(commit)
    echoerr 'git-lineage: Invalid git blame output'
    return
  endif
  var lines = [
    'Commit: ' .. strpart(sha, 0, 7),
    'Author: ' .. commit.author,
    'Date:   ' .. AuthorDate(commit.author_time, commit.author_tz),
    'Title:  ' .. commit.summary,
  ]

  var repo_info = GetRepoInfo(git)
  var host = get(repo_info, 0, '')
  var repo = get(repo_info, 1, '')
  var state: dict<any> = {
    commit_lines: lines,
    sha: sha,
    host: host,
    repo: repo,
    pr_loaded: false,
    pr_lines: [],
    pr_url: '',
  }
  if get(g:, 'git_lineage_show_pr', false) && !empty(host) && !empty(repo)
    LoadPrInfo(state)
  endif

  popup_id = popup_atcursor(PopupLines(state), {
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
    'filter': (id, key) => PopupFilter(id, key, state),
  })
enddef

def ParseBlame(lines: list<string>, sha: string): dict<string>
  var commit: dict<string> = {}
  for line in lines[1 :]
    if line =~ '^\t'
      break
    endif
    var separator = stridx(line, ' ')
    if separator > 0
      commit[strpart(line, 0, separator)] = strpart(line, separator + 1)
    endif
  endfor
  if empty(get(commit, 'author', ''))
      || get(commit, 'author-time', '') !~ '^-\?\d\+$'
      || get(commit, 'author-tz', '') !~ '^[+-]\d\{4}$'
      || !has_key(commit, 'summary')
    return {}
  endif
  return {
    author: commit.author,
    author_time: commit['author-time'],
    author_tz: commit['author-tz'],
    summary: commit.summary == '(' .. sha .. ')' ? '' : commit.summary,
  }
enddef

def AuthorDate(timestamp: string, timezone: string): string
  var sign = timezone[0] == '-' ? -1 : 1
  var offset = sign * (str2nr(timezone[1 : 2]) * 3600
    + str2nr(timezone[3 : 4]) * 60)
  var seconds = str2nr(timestamp) + offset
  var days = seconds / 86400
  if seconds < 0 && seconds % 86400 != 0
    days -= 1
  endif

  # Convert days since 1970-01-01 to a Gregorian calendar date.
  var z = days + 719468
  var era = (z >= 0 ? z : z - 146096) / 146097
  var day_of_era = z - era * 146097
  var year_of_era = (day_of_era - day_of_era / 1460
    + day_of_era / 36524 - day_of_era / 146096) / 365
  var year = year_of_era + era * 400
  var day_of_year = day_of_era
    - (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  var month_part = (5 * day_of_year + 2) / 153
  var day = day_of_year - (153 * month_part + 2) / 5 + 1
  var month = month_part + (month_part < 10 ? 3 : -9)
  year += month <= 2 ? 1 : 0
  return printf('%04d-%02d-%02d', year, month, day)
enddef

def PopupLines(state: dict<any>): list<string>
  var lines = copy(state.commit_lines)
  if state.pr_loaded && !empty(state.pr_lines)
    add(lines, '')
    extend(lines, state.pr_lines)
  endif
  add(lines, '')
  if !empty(state.host) && !empty(state.repo)
    add(lines, 'p: show PR | o: open PR | c: open commit | q/Esc: close')
  else
    add(lines, 'q/Esc: close')
  endif
  return lines
enddef

def LoadPrInfo(state: dict<any>)
  if state.pr_loaded
    return
  endif
  var result = GetPrInfo(state.sha, state.host, state.repo)
  state.pr_loaded = true
  state.pr_lines = result.lines
  state.pr_url = result.url
enddef

def Warn(message: string)
  echohl WarningMsg
  echomsg 'git-lineage: ' .. message
  echohl None
enddef

def BrowserJobExited(browser_job: job, status: number, failure_message: string)
  var job_index = index(browser_jobs, browser_job)
  if job_index >= 0
    remove(browser_jobs, job_index)
  endif
  if status != 0
    Warn(failure_message)
  endif
enddef

def StartBrowserCommand(command: string, failure_message: string)
  var browser_job = job_start([&shell, &shellcmdflag, command], {
    in_io: 'null',
    out_io: 'null',
    err_io: 'null',
    exit_cb: (job, status) => BrowserJobExited(job, status, failure_message),
  })
  add(browser_jobs, browser_job)
  if job_status(browser_job) == 'fail'
    remove(browser_jobs, -1)
    Warn(failure_message)
  endif
enddef

def PopupFilter(id: number, key: string, state: dict<any>): bool
  if key == 'q' || key == "\<Esc>"
    popup_close(id)
    return true
  endif

  if (key == 'p' || key == 'o') && !empty(state.host) && !empty(state.repo)
    LoadPrInfo(state)
    if key == 'p'
      popup_settext(id, PopupLines(state))
    elseif !empty(state.pr_url)
      StartBrowserCommand(
        'gh pr view ' .. shellescape(state.pr_url) .. ' --web',
        'Could not open the PR; check gh authentication and browser settings')
    endif
    return true
  endif

  if key == 'c' && !empty(state.host) && !empty(state.repo)
    if !executable('gh')
      Warn('Install gh to open commits on GitHub')
      return true
    endif
    StartBrowserCommand(
      'gh browse ' .. shellescape(state.sha)
        .. ' --repo ' .. shellescape(state.host .. '/' .. state.repo),
      'Could not open the commit; check gh authentication and browser settings')
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

def GetPrInfo(sha: string, host: string, repo: string): dict<any>
  var result: dict<any> = {lines: [], url: ''}
  if !executable('gh')
    add(result.lines, 'Install gh to show pull request information')
    return result
  endif

  var query =<< trim END
  query($owner: String!, $name: String!, $sha: GitObjectID!) {
    repository(owner: $owner, name: $name) {
      object(oid: $sha) {
        ... on Commit {
          associatedPullRequests(
            first: 2
            orderBy: {field: UPDATED_AT, direction: DESC}
          ) {
            nodes {
              number
              title
              url
              repository {
                isFork
                owner {
                  login
                }
              }
            }
          }
        }
      }
    }
  }
  END

  var query_text = join(query, "\n")
  var repo_parts = split(repo, '/')
  if len(repo_parts) != 2
    return result
  endif

  var owner = repo_parts[0]
  var name = repo_parts[1]

  var request = json_encode({
    query: query_text,
    variables: {
      owner: owner,
      name: name,
      sha: sha,
    },
  })
  var cmd = 'gh api graphql'
    .. ' --hostname ' .. shellescape(host)
    .. ' --method POST'
    .. ' --input -'

  var output = trim(system(cmd, request))

  if v:shell_error != 0
    add(result.lines, 'GitHub API error')
    add(result.lines, 'Check gh authentication or API access for ' .. host)
    return result
  endif

  if empty(output)
    add(result.lines, 'Invalid GitHub API response')
    return result
  endif

  var data: any
  try
    data = json_decode(output)
  catch
    add(result.lines, 'Invalid GitHub API response')
    return result
  endtry
  if type(data) != v:t_dict
      || type(get(data, 'data', 0)) != v:t_dict
      || type(get(data.data, 'repository', 0)) != v:t_dict
      || type(get(data.data.repository, 'object', 0)) != v:t_dict
      || type(get(data.data.repository.object, 'associatedPullRequests', 0)) != v:t_dict
      || type(get(data.data.repository.object.associatedPullRequests, 'nodes', 0)) != v:t_list
    add(result.lines, 'Invalid GitHub API response')
    return result
  endif

  var prs = data.data.repository.object.associatedPullRequests.nodes
  filter(prs, (_, pr) =>
    !pr.repository.isFork || pr.repository.owner.login == owner
  )
  if empty(prs)
    add(result.lines, 'No pull request found')
    return result
  endif

  var pr = prs[0]

  if type(get(pr, 'number', '')) != v:t_number
      || get(pr, 'number', 0) <= 0
      || type(get(pr, 'title', 0)) != v:t_string
      || type(get(pr, 'url', 0)) != v:t_string
    add(result.lines, 'Invalid GitHub API response')
    return result
  endif

  add(result.lines, 'PR #' .. pr.number)
  add(result.lines, 'Title: ' .. substitute(pr.title, '[\r\n\t]', ' ', 'g'))
  add(result.lines, 'URL:   ' .. pr.url)
  result.url = pr.url
  return result
enddef
