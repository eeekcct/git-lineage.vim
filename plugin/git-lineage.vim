if exists('g:loaded_git_lineage')
  finish
endif
if !has('vim9script') || !has('popupwin')
  finish
endif
let g:loaded_git_lineage = 1

highlight default link GitLineagePopup Normal
highlight default link GitLineageBorder Comment

command! GitLineage call git_lineage#Show()
nnoremap <silent> <Plug>(git-lineage) :<C-U>GitLineage<CR>
