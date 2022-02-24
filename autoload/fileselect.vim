vim9script
# File: fileselect.vim
# Author: Yegappan Lakshmanan (yegappan AT yahoo DOT com)
# Version: 1.2
# Last Modified: August 11, 2021
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

# Need Vim 8.2.2261 and higher
if v:version < 802 || !has('patch-8.2.2261')
  finish
endif

var popupTitle: string = ''
var popupID: number = -1
var popupText: list<string> = []
var fileList: list<string> = []
var filterStr: string = ''
var dirQueue: list<string> = []
var refreshTimerID: number = 0
# File names matching this pattern are ignored
var ignoreFilePat: string = '\%(^\..\+\)\|\%(^.\+\.o\)\|\%(^.\+\.obj\)'

def Err(msg: string): void
  echohl ErrorMsg
  echo msg
  echohl None
enddef

# Edit the file selected from the popup menu
def EditFile(id: number, result: number, mods: string): void
  # clear the message displayed at the command-line
  echo ''
  refreshTimerID->timer_stop()
  if result <= 0
    return
  endif
  try
    # if the selected file is already present in a window, then jump to it
    var fname: string = popupText[result - 1]
    var winList: list<number> = fname->bufnr()->win_findbuf()
    if winList->empty()
      # Not present in any window
      if &modified || &buftype != ''
        # the current buffer is modified or is not a normal buffer, then open
        # the file in a new window
        exe mods 'split ' .. popupText[result - 1]
      else
        var editcmd: string = 'confirm '
        if mods != ''
          editcmd ..=  mods .. ' split '
        else
          editcmd ..= 'edit '
        endif
        exe editcmd .. popupText[result - 1]
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
def MakeMenuName(items: list<string>): void
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
      var dirsz: number = (maxwidth - flen - 6) / 2
      dirname = dirname[: dirsz] .. '...' .. dirname[-dirsz :]
    endif
    items[i] = filename
    if dirname != '.'
      items[i] = items[i] .. ' (' .. dirname .. '/)'
    endif
  endfor
enddef

# Handle the keys typed in the popup menu.
# Narrow down the displayed names based on the keys typed so far.
def FilterNames(id: number, key: string): bool
  var update_popup: bool = false
  var key_handled: bool = false

  # To respond to user key-presses in a timely fashion, restart the background
  # timer.
  refreshTimerID->timer_stop()
  if key != "\<Esc>" && dirQueue->len() > 0
    refreshTimerID = timer_start(1'000, TimerCallback)
  endif

  if key == "\<BS>" || key == "\<C-H>"
    # Erase one character from the filter text
    if filterStr->len() >= 1
      filterStr = filterStr[: -2]
      update_popup = true
    endif
    key_handled = true
  elseif key == "\<C-U>"
    # clear the filter text
    filterStr = ''
    update_popup = true
    key_handled = true
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
    key_handled = true
  elseif key == "\<Up>" || key == "\<Down>"
    # Use native Vim handling for these keys
    key_handled = false
  elseif key =~ '^\f$' || key == "\<Space>"
    # Filter the names based on the typed key and keys typed before
    filterStr ..= key
    update_popup = true
    key_handled = true
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
    return true
  endif

  return id->popup_filter_menu(key)
enddef

# Update the popup menu with a list of filenames. If the user entered a filter
# string, then fuzzy match and display only the matching filenames.
def UpdatePopup(): void
  var matchpos: list<list<number>> = []
  if filterStr != ''
    var matches: list<list<any>> = fileList->matchfuzzypos(filterStr)
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
       ->mapnew((i: number, v: string): dict<any> => ({
         text: v,
         props: mapnew(matchpos[i],
                    (_, w: number): dict<any> => ({col: w + 1, length: 1, type: 'fileselect'}))
       }))
  else
    text = items->mapnew((_, v: string): dict<string> => ({text: v}))
  endif
  popupID->popup_settext(text)
enddef

def ProcessDir(dir: string): void
  var dirname: string = dir
  if dirname == ''
    if dirQueue->empty()
      popup_setoptions(popupID, {title: popupTitle})
      return
    endif
    dirname = dirQueue->remove(0)
  endif

  var start: list<any> = reltime()
  while true
    var l: list<dict<any>>

    # Due to a bug in Vim, exceptions from readdirex() cannot be caught.
    # This is fixed by 8.2.1832.
    try
      l = dirname->readdirex()
    catch
      # ignore exceptions in reading directories
    endtry

    if l->empty()
      if dirQueue->empty()
        break
      endif
      dirname = dirQueue->remove(0)
      continue
    endif

    for f in l
      if f.name =~ ignoreFilePat
        continue
      endif

      var filename: string = (dirname == '.') ? '' : dirname .. '/'
      filename ..= f.name
      if f.type == 'dir'
        dirQueue->add(filename)
      else
        fileList->add(filename)
      endif
    endfor
    var elapsed: float = start->reltime()->reltimefloat()
    if elapsed > 0.1 || dirQueue->empty()
      break
    endif
    dirname = dirQueue->remove(0)
  endwhile

  if dirQueue->empty() && fileList->empty()
    Err('No files found')
    return
  endif

  # Expand the file paths and reduce it relative to the home and current
  # directories
  fileList = fileList->map((_, v: string): string => fnamemodify(v, ':p:~:.'))

  UpdatePopup()
  if dirQueue->len() > 0
    refreshTimerID = timer_start(500, TimerCallback)
  else
    popup_setoptions(popupID, {title: popupTitle})
  endif
enddef

var signChars: list<string> = ['―', '\', '|', '/']
var signIdx: number = 0

def GetNextSign(): string
  var sign: string = signChars[signIdx]
  signIdx += 1
  if signIdx >= len(signChars)
    signIdx = 0
  endif
  return sign
enddef

def TimerCallback(timer_id: number): void
  popup_setoptions(popupID,
                   {title: popupTitle .. '[' .. GetNextSign() .. ']'})
  ProcessDir('')
enddef

def GetFiles(start_dir: string): void
  dirQueue = []
  fileList = []
  filterStr = ''
  ProcessDir(start_dir)
enddef

export def FileSelectShowMenu(dir_arg: string, mods: string): void
  var start_dir: string = dir_arg
  if dir_arg == ''
    # default is current directory
    start_dir = getcwd()
  else
    # shorten the directory name relative to the current directory
    start_dir = start_dir->fnamemodify(':p:.')
  endif
  if start_dir[-1 :] == '/'
    # trim the / at the end of the name
    start_dir = start_dir[: -2]
  endif

  # make sure a valid directory is specified
  if start_dir->getftype() != 'dir'
    Err('Error: Invalid directory ' .. start_dir)
    return
  endif

  # Use the directory name as the popup menu title
  if start_dir->len() <= 40
    popupTitle = '[' .. start_dir .. ']'
  else
    # trim the title and show the trailing characters
    popupTitle = '[...' .. start_dir[-37 :] .. ']'
  endif

  # Create the popup menu
  var lnum: number = &lines - &cmdheight - 2 - 10
  var popupAttr: dict<any> = {
      title: popupTitle,
      wrap: 0,
      pos: 'topleft',
      line: lnum,
      col: 2,
      minwidth: 60,
      minheight: 10,
      maxheight: 10,
      maxwidth: 60,
      mapping: 1,
      fixed: 1,
      close: 'button',
      filter: FilterNames,
      callback: (id, result) => EditFile(id, result, mods)
  }
  popupID = popup_menu([], popupAttr)
  prop_type_add('fileselect', {bufnr: popupID->winbufnr(),
                               highlight: 'Title'})

  # Get the list of file names to display.
  GetFiles(start_dir)
  if fileList->empty()
    return
  endif
enddef

# Toggle (open or close) the fileselect popup menu
export def FileSelectToggle(): string
  if popupID->win_gettype() != 'popup'
    # open the file select popup
    FileSelectShowMenu('', '')
  else
    # popup window is present. close it.
    popupID->popup_close(-2)
  endif
  return "\<Ignore>"
enddef

# vim: shiftwidth=2 sts=2 expandtab
