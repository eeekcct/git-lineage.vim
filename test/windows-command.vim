vim9script
import '../autoload/git_lineage/command.vim' as command

if !has('win32')
  throw 'This regression test requires native Windows Vim'
endif
set nomore
set encoding=utf-8
var root = fnamemodify(expand('<sfile>:p'), ':h:h')
var temp = fnamemodify(tempname(), ':p')
var old_path = $PATH
var old_shell = &shell
var old_flag = &shellcmdflag
var old_log = $GIT_LINEAGE_TEST_ARGV
var old_recorder = $GIT_LINEAGE_TEST_RECORDER
var wrappers = temp .. '/wrapper & (test) %PATH% !'
mkdir(wrappers, 'p')
$GIT_LINEAGE_TEST_ARGV = temp .. '/argv.txt'
$GIT_LINEAGE_TEST_RECORDER = root .. '/test/argv-recorder.exe'
var marker = temp .. '/unexpected-command.txt'

# The recorder is a local native executable compiled by the test workflow.
# It records its actual argv, not cmd's textual %* representation.
def Run(prepared: dict<any>, expected: list<string>)
  delete($GIT_LINEAGE_TEST_ARGV)
  var j = job_start(prepared.command, {env: prepared.env,
    in_io: 'null', out_io: 'null', err_io: 'null'})
  var start = reltime()
  while job_status(j) == 'run' && reltimefloat(reltime(start)) < 10
    sleep 10m
  endwhile
  if job_status(j) == 'run'
    job_stop(j)
  endif
  assert_equal('dead', job_status(j))
  assert_equal(0, get(job_info(j), 'exitval', -1))
  assert_true(filereadable($GIT_LINEAGE_TEST_ARGV), 'Recorder ran')
  if filereadable($GIT_LINEAGE_TEST_ARGV)
    assert_equal(expected, readfile($GIT_LINEAGE_TEST_ARGV))
  endif
enddef

try
  var args = ['plain', 'space here', 'a&b', '(parentheses)', '%PATH%', '%1', '%*',
    '!PATH!', '^&', '', 'trailing\', 'space and trailing\', '日本語',
    'x&echo INJECTED>' .. marker, '%PATH%&echo INJECTED>' .. marker]
  for extension in ['cmd', 'bat']
    var wrapper = wrappers .. '/lineage-fixture.' .. extension
    writefile(['@echo off',
      '@"%GIT_LINEAGE_TEST_RECORDER%" %*', 'exit /b %errorlevel%'], wrapper)
    # Neither user shell nor shellcmdflag must affect batch execution.
    for shell in [$SystemRoot .. '\System32\cmd.exe', 'powershell.exe']
      &shell = shell
      &shellcmdflag = shell =~ 'powershell' ? '-NoProfile -Command' : '/c'
      Run(command.Batch(substitute(wrapper, '/', '\\', 'g'), args), args)
      assert_false(filereadable(marker), 'No extra command executed')
    endfor
  endfor
  # Cover real exepath detection, not only the encoder.
  $PATH = wrappers .. ';' .. old_path
  Run(command.Prepare(['lineage-fixture'] + args), args)
  assert_false(filereadable(marker))
  # Native executables retain Vim's direct argv path (including literal quotes).
  # Native Vim's list-command path drops empty arguments; keep its existing
  # behavior out of the batch regression (which checks empty arguments above).
  var native_args = filter(copy(args), (_, value) => !empty(value)) + ['a"b']
  Run(command.Prepare([$GIT_LINEAGE_TEST_RECORDER] + native_args), native_args)
  assert_false(filereadable(marker))
catch
  add(v:errors, v:exception .. ' at ' .. v:throwpoint)
finally
  $PATH = old_path
  &shell = old_shell
  &shellcmdflag = old_flag
  $GIT_LINEAGE_TEST_ARGV = old_log
  $GIT_LINEAGE_TEST_RECORDER = old_recorder
  delete(temp, 'rf')
endtry
if !empty(v:errors)
  writefile(v:errors, root .. '/test-windows-errors.log')
  cquit
endif
qa!
