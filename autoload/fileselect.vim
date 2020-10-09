vim9script
# File: fileselect.vim
# Author: Yegappan Lakshmanan (yegappan AT yahoo DOT com)
# Version: 1.1
# Last Modified: Oct 8, 2020
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

# Need Vim 8.2.1744 and higher
if v:version < 802 || !has('patch-8.2.1744')
  finish
endif

var s:filelist: list<string> = []
var s:popup_text: list<string> = []
var s:filter_text: string = ''
var s:popup_winid: number = -1
var s:pending_dirs: list<string> = []
var s:refresh_timer_id: number = 0
var s:ignore_filepat: string = '\%(^\..\+\)\|\%(^.\+\.o\)'

# Edit the file selected from the popup menu
def EditFile(id: number, result: number)
  # clear the message displayed at the command-line
  echo ''
  s:refresh_timer_id->timer_stop()
  if result <= 0
    return
  endif
  try
    # if the selected file is already present in a window, then jump to it
    var fname: string = s:popup_text[result - 1]
    var winList: list<number> = fname->bufnr()->win_findbuf()
    if winList->len() == 0
      # Not present in any window
      if &modified || &buftype != ''
        # the current buffer is modified or is not a normal buffer, then open
        # the file in a new window
        exe "split " .. popup_text[result - 1]
      else
        exe "confirm edit " .. popup_text[result - 1]
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
def MakeMenuName(items: list<string>)
  var maxwidth: number = popup_winid->popup_getpos().core_width

  var filename: string
  var dirname: string
  var flen: number
  for i in items->len()->range()
    filename = items[i]->fnamemodify(':t')
    flen = filename->len()
    dirname = items[i]->fnamemodify(':h')

    if items[i]->len() > maxwidth && flen < maxwidth
      # keep the full file name and reduce directory name length
      # keep some characters at the beginning and end (equally).
      # 6 spaces are used for "..." and " ()"
      var dirsz = (maxwidth - flen - 6) / 2
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
  var update_popup: number = 0
  var key_handled: number = 0

  # To respond to user key-presses in a timely fashion, restart the background
  # timer.
  s:refresh_timer_id->timer_stop()
  if key != "\<Esc>"
    s:refresh_timer_id = timer_start(1000, function('s:timerCallback'))
  endif

  if key == "\<BS>" || key == "\<C-H>"
    # Erase one character from the filter text
    if filter_text->len() >= 1
      filter_text = filter_text[:-2]
      update_popup = 1
    endif
    key_handled = 1
  elseif key == "\<C-U>"
    # clear the filter text
    filter_text = ''
    update_popup = 1
    key_handled = 1
  elseif key == "\<C-F>"
        || key == "\<C-B>"
        || key == "\<PageUp>"
        || key == "\<PageDown>"
        || key == "\<C-Home>"
        || key == "\<C-End>"
        || key == "\<C-N>"
        || key == "\<C-P>"
    # scroll the popup window
    var cmd: string = 'normal! ' .. (key == "\<C-N>" ? 'j' : key == "\<C-P>" ? 'k' : key)
    cmd->win_execute(s:popup_winid)
    key_handled = 1
  elseif key == "\<Up>" || key == "\<Down>"
    # Use native Vim handling for these keys
    key_handled = 0
  elseif key =~ '^\f$' || key == "\<Space>"
    # Filter the names based on the typed key and keys typed before
    filter_text ..= key
    update_popup = 1
    key_handled = 1
  endif

  if update_popup
    # Update the popup with the new list of file names

    # Keep the cursor at the current item
    var prevSelName: string = ''
    if popup_text->len() > 0
      var curLine: number = line('.', popup_winid)
      prevSelName = popup_text[curLine - 1]
    endif

    if filter_text != ''
      popup_text = filelist->matchfuzzy(filter_text)
    else
      popup_text = filelist
    endif
    var items: list<string> = popup_text->copy()
    MakeMenuName(items)
    id->popup_settext(items)
    echo 'File: ' .. filter_text

    # Select the previously selected entry. If not present, select first entry
    var idx: number = popup_text->index(prevSelName)
    idx = idx == -1 ? 1 : idx + 1
    var cmd: string = 'cursor(' .. idx .. ', 1)'
    cmd->win_execute(popup_winid)
  endif

  if key_handled
    return 1
  endif

  return id->popup_filter_menu(key)
enddef

def s:updatePopup()
  # Expand the file paths and reduce it relative to the home and current
  # directories
  s:filelist = s:filelist->map('fnamemodify(v:val, ":p:~:.")')

  # Save it for later use
  if s:filter_text != ''
    s:popup_text = s:filelist->matchfuzzy(s:filter_text)
  else
    s:popup_text = s:filelist->copy()
  endif

  # Populate the popup menu
  # Split the names into file name and directory path.
  var items: list<string> = s:popup_text->copy()
  MakeMenuName(items)
  s:popup_winid->popup_settext(items)
enddef

def s:processDir(dir_arg: string)
  var dirname: string = dir_arg
  if dirname == ''
    if s:pending_dirs->len() == 0
      return
    endif
    dirname = s:pending_dirs->remove(0)
  endif

  var start = reltime()
  while true
    var l = dirname->readdirex()
    for f in l
      if f.name =~ s:ignore_filepat
        continue
      endif
      var filename = (dirname == '.') ? '' : dirname .. '/'
      filename ..= f.name
      if f.type == 'dir'
        s:pending_dirs->add(filename)
      else
        s:filelist->add(filename)
      endif
    endfor
    var elapsed = start->reltime()->reltimefloat()
    if elapsed > 0.1 || s:pending_dirs->len() == 0
      break
    endif
    dirname = s:pending_dirs->remove(0)
  endwhile

  if s:filelist->len() == 0
    echohl Error | echo "No files found" | echohl None
    return
  endif

  s:updatePopup()
  if s:pending_dirs->len() > 0
    s:refresh_timer_id = timer_start(500, function('s:timerCallback'))
  endif
enddef

def s:timerCallback(timer_id: number)
  s:processDir('')
enddef

def s:getFiles(pat_arg: string)
  s:pending_dirs = []
  s:filelist = []
  s:filter_text = ''
  s:processDir('.')
enddef

def fileselect#showMenu(pat_arg: string)
  # Create the popup menu
  var lnum = &lines - &cmdheight - 2 - 10
  var popupAttr = #{
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
      filter: function("s:filterNames"),
      callback: EditFile
  }
  popup_winid = popup_menu([], popupAttr)

  # Get the list of file names to display.
  s:getFiles(pat_arg)
  if s:filelist->len() == 0
    return
  endif

  echo 'File: ' .. pat_arg
enddef

# Toggle (open or close) the fileselect popup menu
def fileselect#toggle(): string
  if popup_winid->popup_getoptions()->empty()
    # open the file select popup
    fileselect#showMenu('')
  else
    # popup window is present. close it.
    popup_winid->popup_close(-2)
  endif
  return "\<Ignore>"
enddef

# vim: shiftwidth=2 sts=2 expandtab
