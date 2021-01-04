" File: fileselect.vim
" Author: Yegappan Lakshmanan (yegappan AT yahoo DOT com)
" Version: 1.2
" Last Modified: Jan 4, 2021
"
" Plugin to display a list of file names in a popup menu
"
" License:   Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            fileselect plugin is provided *as is* and comes with no warranty
"            of any kind, either expressed or implied. In no event will the
"            copyright holder be liable for any damages resulting from the use
"            of this software.
"
" =========================================================================

" Need Vim 8.2.2261 and higher
if v:version < 802 || !has('patch-8.2.2261')
  finish
endif

" User command to open the file select popup menu
command! -nargs=* -complete=dir Fileselect call fileselect#showMenu(<q-args>)

" key mapping to toggle the file select popup menu
nnoremap <expr> <silent> <Plug>Fileselect_Toggle fileselect#toggle()

" vim: shiftwidth=2 sts=2 expandtab
