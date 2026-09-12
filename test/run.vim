" Run from the repository root: vim -Nu NONE -i NONE -n -es -S test/run.vim
set nocompatible
set nomore
set encoding=utf-8
set noswapfile
set hidden

let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let s:temp = fnamemodify(tempname(), ':p')
let s:old_path = $PATH
let s:old_cwd = getcwd()
let s:old_git_config = $GIT_CONFIG_GLOBAL
let s:old_git_system = $GIT_CONFIG_NOSYSTEM
let s:git = 'git -C ' . shellescape(s:temp . '/repo with spaces')

function! s:Git(args) abort
  let result = system(s:git . ' ' . a:args)
  if v:shell_error
    throw 'Git fixture failed: ' . a:args . ': ' . result
  endif
  return trim(result)
endfunction

function! s:Popup() abort
  let ids = popup_list()
  call assert_equal(1, len(ids), 'Exactly one lineage popup')
  return getbufline(winbufnr(ids[0]), 1, '$')
endfunction

function! s:Response(value) abort
  call writefile([json_encode(a:value)], $GIT_LINEAGE_TEST_RESPONSE)
endfunction

function! s:Run() abort
  call mkdir(s:temp . '/repo with spaces/sub dir', 'p')
  call mkdir(s:temp . '/bin', 'p')
  let $GIT_CONFIG_GLOBAL = s:temp . '/empty.gitconfig'
  let $GIT_CONFIG_NOSYSTEM = '1'
  call writefile([], $GIT_CONFIG_GLOBAL)
  let $GIT_LINEAGE_TEST_RESPONSE = s:temp . '/response.json'
  let $GIT_LINEAGE_TEST_LOG = s:temp . '/gh.log'
  let $GIT_LINEAGE_TEST_EXIT = '0'
  if has('win32')
    let $GIT_LINEAGE_TEST_RESPONSE = substitute($GIT_LINEAGE_TEST_RESPONSE, '/', '\\', 'g')
    call writefile(['@echo off', 'echo %*>>"%GIT_LINEAGE_TEST_LOG%"',
          \ 'if "%~1"=="api" type "%GIT_LINEAGE_TEST_RESPONSE%"',
          \ 'exit /b %GIT_LINEAGE_TEST_EXIT%'], s:temp . '/bin/gh.cmd')
  else
    call writefile(['#!/bin/sh', 'printf ''%s\n'' "$*" >> "$GIT_LINEAGE_TEST_LOG"',
          \ 'if [ "$1" = api ]; then cat "$GIT_LINEAGE_TEST_RESPONSE"; fi',
          \ 'exit "$GIT_LINEAGE_TEST_EXIT"'], s:temp . '/bin/gh')
    call setfperm(s:temp . '/bin/gh', 'rwx------')
  endif
  let $PATH = s:temp . '/bin' . (has('win32') ? ';' : ':') . s:old_path
  call s:Response({})

  runtime plugin/git-lineage.vim
  runtime plugin/git-lineage.vim
  call assert_equal(2, exists(':GitLineage'))
  call assert_match('GitLineage', maparg('<Plug>(git-lineage)', 'n'))
  call assert_equal('', maparg('<Leader>gl', 'n'), 'No default user mapping')
  silent! call assert_fails('GitLineage', 'git-lineage: Open a file first')

  call s:Git('init -b main')
  call s:Git('config user.name "Lineage Test"')
  call s:Git('config user.email lineage@example.invalid')
  call s:Git('config commit.gpgsign false')
  call s:Git('config core.autocrlf false')
  let file = s:temp . '/repo with spaces/sub dir/example file.txt'
  call writefile(['first line', 'second line'], file)
  call s:Git('add .')
  call s:Git('commit -m "First commit"')
  let first_sha = s:Git('rev-parse --short HEAD')
  call writefile(['first line', 'changed second line'], file)
  call writefile(["Subject\twith tab"], s:temp . '/message')
  call s:Git('add .')
  call s:Git('commit -F ' . shellescape(s:temp . '/message'))
  let second_sha = s:Git('rev-parse --short HEAD')

  " The current working directory need not be the file's repository.
  execute 'cd ' . fnameescape(s:root)
  execute 'edit ' . fnameescape(file)
  call cursor(1, 1)
  GitLineage
  call assert_equal('Commit: ' . first_sha, s:Popup()[0])
  call assert_equal('Author: Lineage Test', s:Popup()[1])
  call assert_equal('Title:  First commit', s:Popup()[3])
  let popup_pos = popup_getpos(popup_list()[0])
  let cursor_pos = screenpos(win_getid(), line('.'), col('.'))
  call assert_equal(cursor_pos.col + 10, popup_pos.col, 'Popup starts 10 columns right of cursor')
  call assert_false(filereadable($GIT_LINEAGE_TEST_LOG), 'No remote means no API call')

  call cursor(2, 1)
  GitLineage
  call assert_equal('Commit: ' . second_sha, s:Popup()[0])
  call assert_equal("Title:  Subject\twith tab", s:Popup()[3])
  GitLineage
  call assert_equal(1, len(popup_list()), 'Repeated calls replace the popup')

  " The command follows the saved file. Save edits before relying on line numbers.
  edit!

  call s:Git('remote add origin git@github.com:owner/repo.git')
  call cursor(1, 1)
  GitLineage
  call assert_true(index(s:Popup(), 'No pull request found') >= 0, string(s:Popup()))
  let Filter = popup_getoptions(popup_list()[0]).filter
  call assert_true(Filter(popup_list()[0], 'o'), 'o is consumed even without a PR')

  call s:Response({'number': 42, 'title': "Fix\tquoted \"title\"", 'html_url': 'https://github.com/owner/repo/pull/42'})
  for remote in ['git@github.com:owner/repo.git', 'https://github.com/owner/repo.git/', 'ssh://git@github.com:2222/owner/repo.git']
    call s:Git('remote set-url origin ' . shellescape(remote))
    GitLineage
    call assert_true(index(s:Popup(), 'PR #42') >= 0, remote)
    call assert_true(index(s:Popup(), 'Title: Fix quoted "title"') >= 0)
  endfor
  let Filter = popup_getoptions(popup_list()[0]).filter
  call assert_true(Filter(popup_list()[0], 'o'))
  call assert_match('pr view .*42.* --repo .*github.com/owner/repo.* --web', readfile($GIT_LINEAGE_TEST_LOG)[-1])
  let $GIT_LINEAGE_TEST_EXIT = '1'
  call assert_true(Filter(popup_list()[0], 'o'))
  call assert_match('Could not open the PR', execute('messages'))
  GitLineage
  call assert_equal('Commit: ' . first_sha, s:Popup()[0])
  call assert_true(index(s:Popup(), 'GitHub API error') >= 0)
  let $GIT_LINEAGE_TEST_EXIT = '0'

  for response in ['not json', 'null', '[]', '{"number":"42","title":"x","html_url":"x"}']
    call writefile([response], $GIT_LINEAGE_TEST_RESPONSE)
    GitLineage
    call assert_true(index(s:Popup(), 'Invalid GitHub API response') >= 0, response)
  endfor

  " Remote names may include slashes; tracking remotes take priority over origin.
  call s:Response({})
  call s:Git('remote add team/upstream git@ghe.example.com:team/project.git')
  call s:Git('config branch.main.remote team/upstream')
  call s:Git('config branch.main.merge refs/heads/main')
  GitLineage
  call assert_match('--hostname .*ghe.example.com.* .*repos/team/project/commits/', readfile($GIT_LINEAGE_TEST_LOG)[-1])
  call s:Git('checkout --detach')
  GitLineage
  call assert_match('--hostname .*github.com.* .*repos/owner/repo/commits/', readfile($GIT_LINEAGE_TEST_LOG)[-1])

  let Filter = popup_getoptions(popup_list()[0]).filter
  call assert_true(Filter(popup_list()[0], 'q'))
  call assert_equal([], popup_list())
  GitLineage
  let Filter = popup_getoptions(popup_list()[0]).filter
  call assert_true(Filter(popup_list()[0], "\<Esc>"))
  call assert_equal([], popup_list())

  " Files with different line-ending and BOM settings still work when saved.
  let crlf_file = s:temp . '/repo with spaces/crlf.txt'
  call writefile(["CRLF line\r", "second CRLF line\r"], crlf_file)
  call s:Git('add .')
  call s:Git('commit --allow-empty-message -m ' . shellescape(''))
  execute 'edit ' . fnameescape(crlf_file)
  call assert_equal('dos', &fileformat)
  GitLineage
  call assert_equal('Title:  ', s:Popup()[3])
  call assert_equal('Commit: ' . s:Git('rev-parse --short HEAD'), s:Popup()[0])

  let no_eol_file = s:temp . '/repo with spaces/no-eol.txt'
  call writefile(['no final newline'], no_eol_file, 'b')
  call s:Git('add .')
  call s:Git('commit -m "No final newline"')
  execute 'edit ' . fnameescape(no_eol_file)
  GitLineage
  call assert_equal('Title:  No final newline', s:Popup()[3])

  let bom_file = s:temp . '/repo with spaces/bom.txt'
  call writefile([nr2char(0xfeff) . 'UTF-8 BOM line'], bom_file)
  call s:Git('add .')
  call s:Git('commit -m "UTF-8 BOM"')
  execute 'edit ' . fnameescape(bom_file)
  call assert_true(&bomb)
  GitLineage
  call assert_equal('Title:  UTF-8 BOM', s:Popup()[3])

  " Retain Git access while hiding gh, independently of installed user tools.
  let git_exe = exepath('git')
  call mkdir(s:temp . '/git-only')
  if has('win32')
    call writefile(['@echo off', '@"' . git_exe . '" %*'], s:temp . '/git-only/git.cmd')
  else
    call writefile(['#!/bin/sh', 'exec ' . shellescape(git_exe) . ' "$@"'], s:temp . '/git-only/git')
    call setfperm(s:temp . '/git-only/git', 'rwx------')
  endif
  let fixture_path = $PATH
  let $PATH = s:temp . '/git-only'
  call assert_false(executable('gh'))
  GitLineage
  call assert_true(index(s:Popup(), 'Install gh to show pull request information') >= 0)
  let $PATH = s:temp . '/no-commands'
  silent! call assert_fails('GitLineage', 'git-lineage: git command not found')
  let $PATH = fixture_path

  call writefile(['untracked'], s:temp . '/repo with spaces/untracked.txt')
  execute 'edit ' . fnameescape(s:temp . '/repo with spaces/untracked.txt')
  silent! call assert_fails('GitLineage', 'git-lineage: git blame failed')
  execute 'edit ' . fnameescape(s:temp . '/outside.txt')
  silent! call assert_fails('GitLineage', 'git-lineage: Not inside a Git repository')
  setlocal buftype=nofile
  silent! call assert_fails('GitLineage', 'git-lineage: Open a file first')

  " Generate help tags in the fixture, leaving the working tree clean.
  call mkdir(s:temp . '/doc')
  call writefile(readfile(s:root . '/doc/git-lineage.txt'), s:temp . '/doc/git-lineage.txt')
  execute 'helptags ' . fnameescape(s:temp . '/doc')
  call assert_true(filereadable(s:temp . '/doc/tags'))
endfunction

try
  call s:Run()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
finally
  call popup_clear()
  let $PATH = s:old_path
  let $GIT_CONFIG_GLOBAL = s:old_git_config
  let $GIT_CONFIG_NOSYSTEM = s:old_git_system
  execute 'cd ' . fnameescape(s:old_cwd)
  " Only remove the absolute temporary directory created by this test process.
  if isdirectory(s:temp)
    let resolved = substitute(fnamemodify(s:temp, ':p'), '\\', '/', 'g')
    let expected = substitute(s:temp, '\\', '/', 'g') . '/'
    if resolved ==# expected
      call assert_equal(0, delete(s:temp, 'rf'), 'Remove the test fixture')
    else
      call assert_report('Refusing to remove unexpected fixture path: ' . resolved)
    endif
  endif
endtry

if !empty(v:errors)
  call writefile(v:errors, s:root . '/test-errors.log')
  cquit
endif
call delete(s:root . '/test-errors.log')
qa!
