vim9script
# File: fileselect.vim
# Author: Yegappan Lakshmanan (yegappan AT yahoo DOT com)
# Version: 1.0
# Last Modified: Sep 12, 2020
#
# Plugin to display a list of file names in a popup menu
#
# License:   Permission is hereby granted to use and distribute this code,
#            with or without modifications, provided that this copyright
#            notice is copied with it. Like anything else that's free,
#            fileselect plugin is provided *as is* and comes with no warranty
#            of any kind, either expressed or implied. In no event will the
#            copyright holder be liable for any damages resulting from the use
#            of this software.
#
# =========================================================================

# Popup window support needs Vim 8.2.1665 and higher
if v:version < 802 || !has('patch-8.2.1665')
  finish
endif

# Line continuation used here
let s:cpo_save = &cpo
set cpo&vim

let s:filelist: list<string> = []
let s:popup_text: list<string> = []
let s:filter_text: string = ''
let s:popup_winid: number = -1

# Edit the file selected from the popup menu
def s:editFile(id: number, result: number)
  # clear the message displayed at the command-line
  echo ''
  if result <= 0
    return
  endif
  try
    # if the selected file is already present in a window, then jump to it
    let fname: string = s:popup_text[result - 1]
    let winList: list<number> = fname->bufnr()->win_findbuf()
    if winList->len() == 0
      # Not present in any window
      if &modified || &buftype != ''
        # the current buffer is modified or is not a normal buffer, then open
        # the file in a new window
        exe "split " .. s:popup_text[result - 1]
      else
        exe "confirm edit " .. s:popup_text[result - 1]
      endif
    else
      winList[0]->win_gotoid()
    endif
  catch
    # ignore exceptions
  endtry
enddef

# Convert each file name in the items List into <filename> (<dirname>) format.
# Make sure the popup does't occupy the entire screen by reducing the width.
def s:makeMenuName(items: list<string>)
  let maxwidth: number = s:popup_winid->popup_getpos().core_width

  let filename: string
  let dirname: string
  let flen: number
  for i in items->len()->range()
    filename = items[i]->fnamemodify(':t')
    flen = filename->len()
    dirname = items[i]->fnamemodify(':h')

    if items[i]->len() > maxwidth && flen < maxwidth
      # keep the full file name and reduce directory name length
      # keep some characters at the beginning and end (equally).
      # 6 spaces are used for "..." and " ()"
      let dirsz = (maxwidth - flen - 6) / 2
      dirname = dirname[:dirsz] .. '...' .. dirname[-dirsz:]
    endif
    items[i] = filename
    if dirname != '.'
      items[i] = items[i] .. ' (' .. dirname .. '/)'
    endif
  endfor
enddef

# Handle the keys typed in the popup menu.
# Narrow down the displayed names based on the keys typed so far.
def s:filterNames(id: number, key: string): number
  let update_popup: number = 0
  let key_handled: number = 0

  if key == "\<BS>" || key == "\<C-H>"
    # Erase one character from the filter text
    if s:filter_text->len() >= 1
      s:filter_text = s:filter_text[:-2]
      update_popup = 1
    endif
    key_handled = 1
  elseif key == "\<C-U>"
    # clear the filter text
    s:filter_text = ''
    update_popup = 1
    key_handled = 1
  elseif key == "\<C-F>"
        \ || key == "\<C-B>"
        \ || key == "<PageUp>"
        \ || key == "<PageDown>"
        \ || key == "<C-Home>"
        \ || key == "<C-End>"
        || key == "\<C-N>"
        || key == "\<C-P>"
    # scroll the popup window
    let cmd: string = 'normal! ' .. (key == "\<C-N>" ? 'j' : key == "\<C-P>" : 'k' : key)
    cmd->win_execute(s:popup_winid)
    key_handled = 1
  elseif key == "\<Up>" || key == "\<Down>"
    # Use native Vim handling for these keys
    key_handled = 0
  elseif key =~ '^\f$' || key == "\<Space>"
    # Filter the names based on the typed key and keys typed before
    s:filter_text ..= key
    update_popup = 1
    key_handled = 1
  endif

  if update_popup
    # Update the popup with the new list of file names

    # Keep the cursor at the current item
    let prevSelName: string = ''
    if s:popup_text->len() > 0
      let curLine: number = line('.', s:popup_winid)
      prevSelName = s:popup_text[curLine - 1]
    endif

    if s:filter_text != ''
      s:popup_text = s:filelist->matchfuzzy(s:filter_text)
    else
      s:popup_text = s:filelist
    endif
    let items: list<string> = s:popup_text->copy()
    s:makeMenuName(items)
    id->popup_settext(items)
    echo 'File: ' .. s:filter_text

    # Select the previously selected entry. If not present, select first entry
    let idx: number = s:popup_text->index(prevSelName)
    idx = idx == -1 ? 1 : idx + 1
    let cmd: string = 'cursor(' .. idx .. ', 1)'
    cmd->win_execute(s:popup_winid)
  endif

  if key_handled
    return 1
  endif

  return id->popup_filter_menu(key)
enddef

def fileselect#showMenu(pat_arg: string)
  # Get the list of file names to display.

  # Default pattern to get all the filenames in the current directory tree.
  let pat: string = '**/*'
  if pat_arg != ''
    # use the user specified pattern
    pat = '**/*' .. pat_arg .. '*'
  endif

  let save_wildignore = &wildignore
  set wildignore=*.o,*.obj,*.swp,*.bak,*.~
  let l: list<string> = pat->glob(0, 1)
  &wildignore = save_wildignore
  if l->empty()
    echohl Error | echo "No files found" | echohl None
    return
  endif

  # Remove all the directory names
  l->filter('!isdirectory(v:val)')

  # Expand the file paths and reduce it relative to the home and current
  # directories
  s:filelist = l->map('fnamemodify(v:val, ":p:~:.")')

  # Save it for later use
  s:popup_text = s:filelist->copy()
  s:filter_text = ''

  # Create the popup menu
  let lnum = &lines - &cmdheight - 2 - 10
  let popupAttr = #{
      title: 'File Selector',
      wrap: 0,
      pos: 'topleft',
      line: lnum,
      col: 2,
      minwidth: 60,
      minheight: 10,
      maxheight: 10,
      maxwidth: 60,
      fixed: 1,
      close: "button",
      filter: function('s:filterNames'),
      callback: function('s:editFile')
  }
  s:popup_winid = popup_menu([], popupAttr)

  # Populate the popup menu
  # Split the names into file name and directory path.
  let items: list<string> = s:popup_text->copy()
  s:makeMenuName(items)
  s:popup_winid->popup_settext(items)
  echo 'File: '
enddef

# Toggle (open or close) the fileselect popup menu
def fileselect#toggle()
  if s:popup_winid->popup_getoptions()->empty()
    # open the file select popup
    fileselect#showMenu('')
  else
    # popup window is present. close it.
    s:popup_winid->popup_close(-2)
  endif
enddef

# restore 'cpo'
&cpo = s:cpo_save

# vim: shiftwidth=2 sts=2 expandtab
