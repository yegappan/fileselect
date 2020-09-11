
The File Selector plugin provides an easy access to edit a file from
the current directory tree.

This plugin needs Vim 8.2.1665 and above and will work on all the platforms
where Vim is supported. This plugin will work in both console and GUI Vim.

The command :Fileselect opens a popup menu with a list of file names from the
current directory tree.  When you press <Enter> on a file name, the file is
opened. If the selected file is already opened in a window, the cursor will
move to that window.  If the file is not present in any of the windows, then
the selected file will be opened in the current window.  You can use the up and
down arrow keys to move the currently selected entry in the popup menu.

In the popup menu, you can type a series of characters to narrow down the list
of displayed file names. The characters entered so far is displayed in the
command-line. You can press backspace to erase the previously entered set of
characters. The popup menu displays all the file names containing the series of
typed characters.

You can close the popup menu by pressing the escape key or by pressing CTRL-C.

In the popup menu, the complete directory path to a file is displayed in
parenthesis after the file name. If this is too long, then the path is
shortened and an abbreviated path is displayed.
