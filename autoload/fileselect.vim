" File: fileselect.vim
" Author: Yegappan Lakshmanan (yegappan AT yahoo DOT com)
" Version: 1.0
" Last Modified: Sep 11, 2020
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

" Popup window support needs Vim 8.2.1665 and higher
if v:version < 802 || !has('patch-8.2.1665')
  finish
endif

" Line continuation used here
let s:cpo_save = &cpo
set cpo&vim

let s:filelist = []
let s:popup_text = []
let s:filter_text = ''
let s:popup_winid = -1

" Edit the file selected from the popup menu
func s:editFile(id, result) abort
  if a:result <= 0
    return
  endif
  try
    " if the selected file is already present in a window, then jump to it
    let fname = s:popup_text[a:result - 1]
    let winList = win_findbuf(bufnr(fname))
    if len(winList) == 0
      " Not present in any window
      exe "confirm edit " .. s:popup_text[a:result - 1]
    else
      call win_gotoid(winList[0])
    endif
  catch
    " ignore exceptions
  endtry
endfunc

" Convert each file name in the items List into <filename> (<dirname>) format.
" Make sure the popup does't occupy the entire screen by reducing the width.
func s:makeMenuName(items) abort
  let maxwidth = popup_getpos(s:popup_winid).core_width
  "let maxwidth = &columns - 30

  for i in range(len(a:items))
    let filename = fnamemodify(a:items[i], ':t')
    let flen = len(filename)
    let dirname = fnamemodify(a:items[i], ':h')

    if len(a:items[i]) > maxwidth && flen < maxwidth
      " keep the full file name and reduce directory name length
      " keep some characters at the beginning and end (equally).
      " 6 spaces are used for "..." and " ()"
      let dirsz = (maxwidth - flen - 6) / 2
      let dirname = dirname[:dirsz] .. '...' .. dirname[-dirsz:]
    endif
    let a:items[i] = filename
    if dirname != '.'
      let a:items[i] ..= ' (' .. dirname .. '/)'
    endif
  endfor
endfunc

" Handle the keys typed in the popup menu.
" Narrow down the displayed names based on the keys typed so far.
func s:filterNames(id, key) abort
  let update_popup = 0
  let key_handled = 0

  if a:key == "\<BS>"
    " Erase one character from the filter text
    if len(s:filter_text) >= 1
      let s:filter_text = s:filter_text[:-2]
      let update_popup = 1
    endif
    let key_handled = 1
  elseif a:key == "\<C-U>"
    let s:filter_text = ''
    let update_popup = 1
    let key_handled = 1
  elseif a:key == "\<C-F>"
        \ || a:key == "\<C-B>"
        \ || a:key == "<PageUp>"
        \ || a:key == "<PageDown>"
        \ || a:key == "<C-Home>"
        \ || a:key == "<C-End>"
    call win_execute(s:popup_winid, 'normal! ' .. a:key)
    let key_handled = 1
  elseif a:key == "\<Up>"
        \ || a:key == "\<Down>"
    " Use native Vim handling of these keys
    let key_handled = 0
  elseif a:key =~ '^\f$' || a:key == "\<Space>"
    " Filter the names based on the typed key and keys typed before
    let s:filter_text ..= a:key
    let update_popup = 1
    let key_handled = 1
  endif

  if update_popup
    " Update the popup with the new list of file names

    " Keep the cursor at the current item
    if len(s:popup_text) > 0
      let curLine = line('.', s:popup_winid)
      let prevSelName = s:popup_text[curLine - 1]
    else
      let prevSelName = ''
    endif

    if s:filter_text != ''
      let s:popup_text = s:filelist->matchfuzzy(s:filter_text)
    else
      let s:popup_text = s:filelist
    endif
    let items = copy(s:popup_text)
    call s:makeMenuName(items)
    call popup_settext(a:id, items)
    echo s:filter_text

    " Select the previously selected entry. If not present, select first entry
    let idx = index(s:popup_text, prevSelName)
    let idx = idx == -1 ? 1 : idx + 1
    call win_execute(s:popup_winid, idx)
  endif

  if key_handled
    return 1
  endif

  return popup_filter_menu(a:id, a:key)
endfunc

func fileselect#showMenu(pat_arg) abort
  " Get the list of file names to display.
  if a:pat_arg != ''
    let pat = '**/*' .. a:pat_arg .. '*'
  else
    let pat = '**/*'
  endif
  let save_wildignore = &wildignore
  set wildignore=*.o,*.obj,*.swp,*.bak,*.~
  let l = glob(pat, 0, 1)
  let &wildignore = save_wildignore
  if empty(l)
    echohl Error | echo "No files found" | echohl None
    return
  endif

  " Remove all directory names
  eval l->filter('!isdirectory(v:val)')

  " Expand the file paths and reduce it relative to the home and current
  " directories
  let s:filelist = map(l, 'fnamemodify(v:val, ":p:~:.")')

  " Save it for later use
  let s:popup_text = copy(s:filelist)

  " Create the popup menu
  let lnum = &lines - &cmdheight - 2 - 10
  let popupAttr = {}
  let popupAttr.title = 'File Selector'
  let popupAttr.wrap = 0
  let popupAttr.pos = 'topleft'
  let popupAttr.line = lnum
  let popupAttr.col = 2
  let popupAttr.minwidth = 60
  let popupAttr.minheight = 10
  let popupAttr.maxheight = 10
  let popupAttr.maxwidth = 60
  let popupAttr.fixed = 1
  let popupAttr.close = "button"
  let popupAttr.filter = function('s:filterNames')
  let popupAttr.callback = function('s:editFile')
  let s:popup_winid = popup_menu([], popupAttr)

  " Populate the popup menu
  " Split the names into file name and directory path.
  let items = copy(s:popup_text)
  call s:makeMenuName(items)
  call popup_settext(s:popup_winid, items)
endfunc

" Toggle (open or close) the fileselect popup menu
func fileselect#toggle() abort
  if empty(popup_getoptions(s:popup_winid))
    " open the file select popup
    call fileselect#showMenu('')
  else
    " popup window is present. close it.
    call popup_close(s:popup_winid, -2)
  endif
endfunc

" restore 'cpo'
let &cpo = s:cpo_save
unlet s:cpo_save

" vim: shiftwidth=2 sts=2 expandtab
