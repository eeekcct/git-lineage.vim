vim9script
import '../autoload/git_lineage/command.vim' as command

var old_root = $SystemRoot
if !has('win32')
  $SystemRoot = 'C:\Windows'
endif
var result = command.Batch('C:\tools\git.cmd', ['space here', '%PATH%', '!x!', 'a&b', '', 'last\'])
assert_equal('space here', result.env.GIT_LINEAGE_ARG_1)
assert_equal('%PATH%', result.env.GIT_LINEAGE_ARG_2)
assert_equal('!x!', result.env.GIT_LINEAGE_ARG_3)
assert_equal('a&b', result.env.GIT_LINEAGE_ARG_4)
assert_false(has_key(result.env, 'GIT_LINEAGE_ARG_5'))
assert_equal('last\\', result.env.GIT_LINEAGE_ARG_6)
assert_match('/d /e:on /v:off /s /c ', result.command)
assert_match('""', result.command)
assert_notmatch('%PATH%\|space here\|a&b', result.command)
for value in ['a"b', "a\nb", "a\rb", "a\tb", nr2char(1), repeat('a', 8001)]
  var rejected = false
  try
    command.Batch('C:\tools\git.cmd', [value])
  catch
    rejected = true
  endtry
  assert_true(rejected, 'Reject unsafe/oversized batch argument: ' .. string(value))
endfor
$SystemRoot = old_root
if !empty(v:errors)
  writefile(v:errors, 'test-command-errors.log')
  cquit
endif
qa!
