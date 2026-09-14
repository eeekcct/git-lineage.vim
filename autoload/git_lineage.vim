vim9script

var popup_id = 0
var browser_jobs: list<job> = []

def CommandOutput(context: dict<any>, channel: channel, message: string)
  add(context.stdout, substitute(message, '\r$', '', ''))
enddef

def FinishCommand(context: dict<any>)
  if context.finished || !context.exited || !context.closed
    return
  endif
  context.finished = true
  context.callback(context)
enddef

def CommandExited(context: dict<any>, command_job: job, status: number)
  context.status = status
  context.exited = true
  FinishCommand(context)
enddef

def CommandClosed(context: dict<any>, channel: channel)
  context.closed = true
  FinishCommand(context)
enddef

def PrepareCommand(arguments: list<string>): any
  var command_arguments = copy(arguments)
  var executable_path = exepath(command_arguments[0])
  if has('win32') && executable_path =~? '\.\%(cmd\|bat\)$'
    return [&shell, &shellcmdflag, join(arguments, ' ')]
  endif
  if !empty(executable_path)
    command_arguments[0] = executable_path
  endif
  return command_arguments
enddef

def StartCommand(arguments: list<string>, input: string, Callback: func): job
  var context: dict<any> = {
    stdout: [],
    status: -1,
    exited: false,
    closed: false,
    finished: false,
    callback: Callback,
  }
  var command_job = job_start(PrepareCommand(arguments), {
    in_io: empty(input) ? 'null' : 'pipe',
    out_io: 'pipe',
    err_io: 'null',
    out_mode: 'nl',
    out_cb: (channel, message) => CommandOutput(context, channel, message),
    exit_cb: (job, status) => CommandExited(context, job, status),
    close_cb: (channel) => CommandClosed(context, channel),
  })

  if job_status(command_job) == 'fail'
    context.exited = true
    context.closed = true
    FinishCommand(context)
  elseif !empty(input)
    var channel = job_getchannel(command_job)
    ch_sendraw(channel, input)
    ch_close_in(channel)
  endif
  return command_job
enddef

def StateIsOpen(state: dict<any>): bool
  return !state.closed && popup_id == state.popup_id
enddef

def UpdatePopup(state: dict<any>)
  if StateIsOpen(state)
    popup_settext(state.popup_id, PopupLines(state))
  endif
enddef

def StartStateCommand(state: dict<any>, arguments: list<string>, input: string, Callback: func)
  var command_job = StartCommand(arguments, input, Callback)
  add(state.jobs, command_job)
enddef

def CancelStateJobs(state: dict<any>)
  for command_job in state.jobs
    if job_status(command_job) == 'run'
      job_stop(command_job)
    endif
  endfor
enddef

def PopupClosed(id: number, result: number, state: dict<any>)
  state.closed = true
  CancelStateJobs(state)
  if popup_id == id
    popup_id = 0
  endif
enddef

def FailState(state: dict<any>, message: string)
  if !StateIsOpen(state)
    return
  endif
  state.loading = false
  state.repo_loading = false
  state.repo_loaded = true
  state.commit_lines = ['Error: ' .. message]
  Warn(message)
  UpdatePopup(state)
enddef

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

  var git = ['git', '--no-pager', '--literal-pathspecs',
    '-C', fnamemodify(file, ':h')]
  var lnum = line('.')
  var state: dict<any> = {
    commit_lines: [],
    sha: '',
    host: '',
    repo: '',
    git: git,
    loading: true,
    repo_loading: false,
    repo_loaded: false,
    pr_loaded: false,
    pr_loading: false,
    pr_lines: [],
    pr_url: '',
    open_pr_when_loaded: false,
    show_pr_when_loaded: false,
    jobs: [],
    closed: false,
    popup_id: 0,
  }

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
    'callback': (id, result) => PopupClosed(id, result, state),
    'filtermode': 'n',
    'filter': (id, key) => PopupFilter(id, key, state),
  })
  state.popup_id = popup_id
  var blame_arguments = git + ['blame', '--porcelain',
    '-L', lnum .. ',' .. lnum, '--', fnamemodify(file, ':t')]
  StartStateCommand(state, blame_arguments, '',
    (context) => BlameExited(state, context))
enddef

def BlameExited(state: dict<any>, context: dict<any>)
  if !StateIsOpen(state)
    return
  endif
  if context.status != 0 || empty(context.stdout)
    StartStateCommand(state, state.git + ['rev-parse', '--is-inside-work-tree'], '',
      (repo_context) => RepoCheckExited(state, repo_context))
    return
  endif

  var sha = split(context.stdout[0])[0]
  if sha =~ '^0\+$'
    FailState(state, 'Current line is not committed yet')
    return
  endif

  var commit = ParseBlame(context.stdout, sha)
  if empty(commit)
    FailState(state, 'Invalid git blame output')
    return
  endif

  state.sha = sha
  state.commit_lines = [
    'Commit: ' .. strpart(sha, 0, 7),
    'Author: ' .. commit.author,
    'Date:   ' .. AuthorDate(commit.author_time, commit.author_tz),
    'Title:  ' .. commit.summary,
  ]
  state.loading = false
  UpdatePopup(state)
  StartRepoInfo(state)
enddef

def RepoCheckExited(state: dict<any>, context: dict<any>)
  if context.status != 0 || empty(context.stdout)
      || trim(context.stdout[0]) != 'true'
    FailState(state, 'Not inside a Git repository')
  else
    FailState(state,
      'git blame failed; the file must be tracked with committed history')
  endif
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
  if state.loading
    return ['Loading commit information...', '', 'q/Esc: close']
  endif

  var lines = copy(state.commit_lines)
  if state.pr_loading && state.show_pr_when_loaded
    add(lines, '')
    add(lines, 'Loading pull request information...')
  elseif state.pr_loaded && state.show_pr_when_loaded && !empty(state.pr_lines)
    add(lines, '')
    extend(lines, state.pr_lines)
  endif
  add(lines, '')
  if state.repo_loading
    add(lines, 'Resolving repository... | q/Esc: close')
  elseif !empty(state.host) && !empty(state.repo)
    add(lines, 'p: show PR | o: open PR | c: open commit | q/Esc: close')
  else
    add(lines, 'q/Esc: close')
  endif
  return lines
enddef

def LoadPrInfo(state: dict<any>, open_when_loaded: bool = false,
    show_when_loaded: bool = false)
  if open_when_loaded
    state.open_pr_when_loaded = true
  endif
  if show_when_loaded
    state.show_pr_when_loaded = true
  endif
  if state.pr_loaded
    if show_when_loaded
      UpdatePopup(state)
    endif
    if open_when_loaded && !empty(state.pr_url)
      StartBrowserCommand(
        ['gh', 'pr', 'view', state.pr_url, '--web'],
        'Could not open the PR; check gh authentication and browser settings')
    endif
    return
  endif
  if state.pr_loading
    return
  endif
  if !executable('gh')
    state.pr_loaded = true
    state.pr_lines = ['Install gh to show pull request information']
    if state.show_pr_when_loaded
      UpdatePopup(state)
    endif
    return
  endif

  var repo_parts = split(state.repo, '/')
  if len(repo_parts) != 2
    state.pr_loaded = true
    return
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
  var request = json_encode({
    query: join(query, "\n"),
    variables: {
      owner: repo_parts[0],
      name: repo_parts[1],
      sha: state.sha,
    },
  })
  state.pr_loading = true
  if state.show_pr_when_loaded
    UpdatePopup(state)
  endif
  StartStateCommand(state, [
    'gh', 'api', 'graphql',
    '--hostname', state.host,
    '--method', 'POST',
    '--input', '-',
  ], request, (context) => PrInfoExited(state, repo_parts[0], context))
enddef

def PrInfoExited(state: dict<any>, owner: string, context: dict<any>)
  if !StateIsOpen(state)
    return
  endif
  var result = ParsePrInfo(
    join(context.stdout, "\n"), context.status, owner, state.host)
  state.pr_loading = false
  state.pr_loaded = true
  state.pr_lines = result.lines
  state.pr_url = result.url
  if state.show_pr_when_loaded
    UpdatePopup(state)
  endif
  if state.open_pr_when_loaded && !empty(state.pr_url)
    StartBrowserCommand(
      ['gh', 'pr', 'view', state.pr_url, '--web'],
      'Could not open the PR; check gh authentication and browser settings')
  endif
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

def StartBrowserCommand(arguments: list<string>, failure_message: string)
  var browser_job = job_start(PrepareCommand(arguments), {
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
    LoadPrInfo(state, key == 'o', key == 'p')
    return true
  endif

  if key == 'c' && !empty(state.host) && !empty(state.repo)
    if !executable('gh')
      Warn('Install gh to open commits on GitHub')
      return true
    endif
    StartBrowserCommand(
      ['gh', 'browse', state.sha, '--repo', state.host .. '/' .. state.repo],
      'Could not open the commit; check gh authentication and browser settings')
    return true
  endif
  return false
enddef

def StartRepoInfo(state: dict<any>)
  if !StateIsOpen(state)
    return
  endif
  state.repo_loading = true
  UpdatePopup(state)
  StartStateCommand(state, state.git
    + ['symbolic-ref', '--quiet', '--short', 'HEAD'], '',
    (context) => BranchExited(state, context))
enddef

def BranchExited(state: dict<any>, context: dict<any>)
  if !StateIsOpen(state)
    return
  endif
  state.branch = context.status == 0 && !empty(context.stdout)
    ? trim(context.stdout[0]) : ''
  StartStateCommand(state, state.git + [
    'config', '--get-regexp', '^(branch\..*\.remote|remote\..*\.url)$',
  ], '', (config_context) => RepoConfigExited(state, config_context))
enddef

def RepoConfigExited(state: dict<any>, context: dict<any>)
  if !StateIsOpen(state)
    return
  endif

  var branch_remote = ''
  var remote_urls: dict<string> = {}
  for config_line in context.stdout
    var separator = stridx(config_line, ' ')
    if separator <= 0
      continue
    endif
    var key = strpart(config_line, 0, separator)
    var value = strpart(config_line, separator + 1)
    if !empty(state.branch) && key == 'branch.' .. state.branch .. '.remote'
      branch_remote = value
    elseif key =~ '^remote\..*\.url$'
      var remote_name = strpart(key, 7, strlen(key) - 11)
      if !has_key(remote_urls, remote_name)
        remote_urls[remote_name] = value
      endif
    endif
  endfor

  var remote_name = !empty(branch_remote) && branch_remote != '.'
    ? branch_remote : (has_key(remote_urls, 'origin') ? 'origin' : '')
  var repo_info = empty(remote_name) || !has_key(remote_urls, remote_name)
    ? [] : ParseRemoteUrl(remote_urls[remote_name])
  state.host = get(repo_info, 0, '')
  state.repo = get(repo_info, 1, '')
  state.repo_loading = false
  state.repo_loaded = true
  UpdatePopup(state)
  if get(g:, 'git_lineage_show_pr', false)
      && !empty(state.host) && !empty(state.repo)
    LoadPrInfo(state, false, true)
  endif
enddef

def ParseRemoteUrl(url: string): list<string>
  var remote = url
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

def ParsePrInfo(output_text: string, status: number, owner: string,
    host: string): dict<any>
  var result: dict<any> = {lines: [], url: ''}
  if status != 0
    add(result.lines, 'GitHub API error')
    add(result.lines, 'Check gh authentication or API access for ' .. host)
    return result
  endif

  var output = trim(output_text)
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
