vim9script

# cmd.exe expands %variables% once, even inside double quotes. Keep user data
# out of its command source by supplying it through this job's environment.
# The trusted batch wrapper must forward %* without CALL/re-parsing or enabling
# delayed expansion. This cannot make an arbitrary batch program safe.
export def Batch(executable_path: string, arguments: list<string>): dict<any>
  var cmd = $SystemRoot .. '\System32\cmd.exe'
  if empty($SystemRoot) || cmd =~ '["\r\n]'
    throw 'Cannot locate the Windows command processor safely'
  endif
  var values = [executable_path] + arguments
  var environment: dict<string> = {}
  var words: list<string> = []
  var expanded_length = strlen(cmd) + 32
  for i in range(len(values))
    var value = values[i]
    # Quotes can break the surrounding cmd quotes; control characters can
    # truncate or split a command. Neither is a supported Windows pathname.
    if value =~ '["\x00-\x1f\x7f]'
      throw 'Cannot safely pass quotes or control characters to a Windows batch wrapper'
    endif
    if i == 0 && (empty(value) || value =~ '\\$')
      throw 'Invalid Windows batch wrapper path'
    endif
    if i > 0
      # A normal %* wrapper forwards the quoted argument to a native program.
      # Double trailing backslashes for that program's Windows argv parser.
      value = substitute(value, '\\*$', '&&', '')
    endif
    expanded_length += strlen(value) + 3
    if expanded_length > 8000
      throw 'Windows batch command exceeds the safe command-line length'
    endif
    if empty(value)
      add(words, '""')
    else
      var name = 'GIT_LINEAGE_ARG_' .. i
      environment[name] = value
      add(words, '"%' .. name .. '%"')
    endif
  endfor
  var source = '"' .. cmd .. '" /d /e:on /v:off /s /c "' .. join(words, ' ') .. '"'
  if strlen(source) > 8000
    throw 'Windows batch command exceeds the safe command-line length'
  endif
  return {
    command: source,
    env: environment,
  }
enddef

export def Prepare(arguments: list<string>): dict<any>
  var command_arguments = copy(arguments)
  var executable_path = exepath(command_arguments[0])
  if has('win32') && executable_path =~? '\.\%(cmd\|bat\)$'
    return Batch(executable_path, arguments[1 :])
  endif
  if !empty(executable_path)
    command_arguments[0] = executable_path
  endif
  return {command: command_arguments, env: {}}
enddef
