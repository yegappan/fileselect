vim9script
# File: fileselect.vim
# Author: Yegappan Lakshmanan (yegappan AT yahoo DOT com)
# Version: 1.2
# Last Modified: Oct 10, 2020
#
# Plugin to display a list of file names in a popup menu.
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

var popupTitle: string = ''
var popupID: number = -1
var popupText: list<string> = []
var fileList: list<string> = []
var filterStr: string = ''
var dirQueue: list<string> = []
var refreshTimer: number = 0
# File names matching this pattern are ignored
var ignoreFilePat: string = '\%(^\..\+\)\|\%(^.\+\.o\)\|\%(^.\+\.obj\)'

def Err(msg: string)
  echohl Error
  echo msg
  echohl None
enddef

# Edit the file selected from the popup menu
def EditFile(id: number, result: number)
  # clear the message displayed at the command-line
  echo ''
  refreshTimer->timer_stop()
  if result <= 0
    return
  endif
  try
    # if the selected file is already present in a window, then jump to it
    var fname: string = popupText[result - 1]
    var winList: list<number> = fname->bufnr()->win_findbuf()
    if winList->len() == 0
      # Not present in any window
      if &modified || &buftype != ''
        # the current buffer is modified or is not a normal buffer, then open
        # the file in a new window
        exe "split " .. popupText[result - 1]
      else
        exe "confirm edit " .. popupText[result - 1]
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
  var maxwidth: number = popupID->popup_getpos().core_width

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
def FilterNames(id: number, key: string): number
  var update_popup: number = 0
  var key_handled: number = 0

  # To respond to user key-presses in a timely fashion, restart the background
  # timer.
  refreshTimer->timer_stop()
  if key != "\<Esc>" && dirQueue->len() > 0
    refreshTimer = timer_start(1000, TimerCallback)
  endif

  if key == "\<BS>" || key == "\<C-H>"
    # Erase one character from the filter text
    if filterStr->len() >= 1
      filterStr = filterStr[:-2]
      update_popup = 1
    endif
    key_handled = 1
  elseif key == "\<C-U>"
    # clear the filter text
    filterStr = ''
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
    cmd->win_execute(popupID)
    key_handled = 1
  elseif key == "\<Up>" || key == "\<Down>"
    # Use native Vim handling for these keys
    key_handled = 0
  elseif key =~ '^\f$' || key == "\<Space>"
    # Filter the names based on the typed key and keys typed before
    filterStr ..= key
    update_popup = 1
    key_handled = 1
  endif

  if update_popup
    # Update the popup with the new list of file names

    # Keep the cursor at the current item
    var prevSelName: string = ''
    if popupText->len() > 0
      var curLine: number = line('.', popupID)
      prevSelName = popupText[curLine - 1]
    endif

    UpdatePopup()
    echo 'Filter: ' .. filterStr

    # Select the previously selected entry. If not present, select first entry
    var idx: number = popupText->index(prevSelName)
    idx = idx == -1 ? 1 : idx + 1
    var cmd: string = 'cursor(' .. idx .. ', 1)'
    cmd->win_execute(popupID)
  endif

  if key_handled
    return 1
  endif

  return id->popup_filter_menu(key)
enddef

# Update the popup menu with a list of filenames. If the user entered a filter
# string, then fuzzy match and display only the matching filenames.
def UpdatePopup()
  var matchpos: list<list<number>> = []
  if filterStr != ''
    var matches: list<any> = fileList->matchfuzzypos(filterStr)
    popupText = matches[0]
    matchpos = matches[1]
  else
    popupText = fileList->copy()
  endif

  # Populate the popup menu
  var items: list<string> = popupText->copy()

  # Split the names into file name and directory path.
  # FIXME: Changing how a filename is displayed in the popup menu breaks the
  # highlighting of the fuzzy matching positions. For now, display the
  # unmodified filename with the full path in the popup menu
  #MakeMenuName(items)

  var text: list<dict<any>>
  if len(matchpos) > 0
    text = items
       ->map({i, v -> #{
         text: v,
         props: map(matchpos[i],
                    {_, w -> #{col: w + 1, length: 1, type: 'fileselect'}})
       }})
  else
    text = items->map({_, v -> #{text: v}})
  endif
  popupID->popup_settext(text)
enddef

def ProcessDir(dir: string)
  var dirname: string = dir
  if dirname == ''
    if dirQueue->len() == 0
      popup_setoptions(popupID, #{title: popupTitle})
      return
    endif
    dirname = dirQueue->remove(0)
  endif

  var start = reltime()
  while true
    var l: list<dict<any>>

    # Due to a bug in Vim, exceptions from readdirex() cannot be caught.
    # This is fixed by 8.2.1832.
    l = dirname->readdirex()

    if l->len() == 0
      if dirQueue->len() == 0
        break
      endif
      dirname = dirQueue->remove(0)
      continue
    endif

    for f in l
      if f.name =~ ignoreFilePat
        continue
      endif

      var filename = (dirname == '.') ? '' : dirname .. '/'
      filename ..= f.name
      if f.type == 'dir'
        dirQueue->add(filename)
      else
        fileList->add(filename)
      endif
    endfor
    var elapsed = start->reltime()->reltimefloat()
    if elapsed > 0.1 || dirQueue->len() == 0
      break
    endif
    dirname = dirQueue->remove(0)
  endwhile

  if dirQueue->len() == 0 && fileList->len() == 0
    Err("No files found")
    return
  endif

  # Expand the file paths and reduce it relative to the home and current
  # directories
  fileList = fileList->map({_, v -> fnamemodify(v, ':p:~:.')})

  UpdatePopup()
  if dirQueue->len() > 0
    refreshTimer = timer_start(500, TimerCallback)
  else
    popup_setoptions(popupID, #{title: popupTitle})
  endif
enddef

var signChars = ['―', '\', '|', '/']
var signIdx = 0

def GetNextSign(): string
  var sign = signChars[signIdx]
  signIdx += 1
  if signIdx >= len(signChars)
    signIdx = 0
  endif
  return sign
enddef

def TimerCallback(timer_id: number)
  popup_setoptions(popupID,
                   #{title: popupTitle .. ' [' .. GetNextSign() .. '] '})
  ProcessDir('')
enddef

def GetFiles(start_dir: string)
  dirQueue = []
  fileList = []
  filterStr = ''
  ProcessDir(start_dir)
enddef

def fileselect#showMenu(dir_arg: string)
  var start_dir = dir_arg
  if dir_arg == ''
    # default is current directory
    start_dir = '.'
  endif
  # shorten the directory name relative to the current directory
  start_dir = start_dir->fnamemodify(':p:.')
  if start_dir[-1:] == '/'
    # trim the / at the end of the name
    start_dir = start_dir[:-2]
  endif

  # make sure a valid directory is specified
  if start_dir->getftype() != 'dir'
    Err("Error: Invalid directory " .. start_dir)
    return
  endif

  # Use the directory name as the popup menu title
  popupTitle = start_dir
  if popupTitle->len() > 40
    # trim the title and show the trailing characters
    popupTitle = '...' .. popupTitle[-37:]
  endif

  # Create the popup menu
  var lnum = &lines - &cmdheight - 2 - 10
  var popupAttr = #{
      title: popupTitle,
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
      filter: FilterNames,
      callback: EditFile
  }
  popupID = popup_menu([], popupAttr)
  prop_type_add('fileselect', #{bufnr: popupID->winbufnr(),
                                highlight: 'Title'})

  # Get the list of file names to display.
  GetFiles(start_dir)
  if fileList->len() == 0
    return
  endif
enddef

# Toggle (open or close) the fileselect popup menu
def fileselect#toggle(): string
  if popupID->popup_getoptions()->empty()
    # open the file select popup
    fileselect#showMenu('')
  else
    # popup window is present. close it.
    popupID->popup_close(-2)
  endif
  return "\<Ignore>"
enddef

# vim: shiftwidth=2 sts=2 expandtab
