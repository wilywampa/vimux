if exists("g:loaded_vimux") || &cp
  finish
endif
let g:loaded_vimux = 1

command -nargs=* VimuxRunCommand :call VimuxRunCommand(<args>)
command VimuxRunLastCommand :call VimuxRunLastCommand()
command VimuxCloseRunner :call VimuxCloseRunner()
command VimuxZoomRunner :call VimuxZoomRunner()
command VimuxInspectRunner :call VimuxInspectRunner()
command VimuxScrollUpInspect :call VimuxScrollUpInspect()
command VimuxScrollDownInspect :call VimuxScrollDownInspect()
command VimuxInterruptRunner :call VimuxInterruptRunner()
command -nargs=? VimuxPromptCommand :call VimuxPromptCommand(<args>)
command VimuxClearRunnerHistory :call VimuxClearRunnerHistory()
command VimuxTogglePane :call VimuxTogglePane()

function! VimuxRunCommandInDir(command, useFile)
    let l:file = ""
    if a:useFile ==# 1
        let l:file = shellescape(expand('%:t'), 1)
    endif
    call VimuxRunCommand("cd ".shellescape(expand('%:p:h'), 1)." && ".a:command." ".l:file." && cd - > /dev/null")
endfunction

function! VimuxRunLastCommand()
  if exists("g:VimuxRunnerIndex") && exists("g:VimuxLastCommand")
    call VimuxRunCommand(g:VimuxLastCommand)
  else
    echo "No last vimux command."
  endif
endfunction

function! VimuxRunCommand(command, ...)
  if !exists("g:VimuxRunnerIndex") || _VimuxHasRunner(g:VimuxRunnerIndex) == -1
    echohl WarningMsg
    echomsg "'g:VimuxRunnerIndex' does not exist"
    echohl None
    return
  endif

  let l:autoreturn = 1
  if exists("a:1")
    let l:autoreturn = a:1
  endif

  let resetSequence = _VimuxOption("g:VimuxResetSequence", "q C-u")

  if VimuxSendKeys(resetSequence)
    return
  endif
  call VimuxSendText(a:command)

  if l:autoreturn == 1
    call VimuxSendKeys("Enter")
  endif
endfunction

function! VimuxSendText(text)
  let text = substitute(a:text, ';$', ';;', '')
  let text = '"'.escape(text, '"$`\').'"'
  if exists("g:VimuxRunnerIndex")
    let zoomed = _VimuxTmuxWindowZoomed()
    let result = _VimuxTmux((zoomed ? "resize-pane -Z \\; " : "" ) .
        \ "send-keys -l -t ".g:VimuxRunnerIndex." -- ".text)
    if zoomed | call _VimuxTmux("resize-pane -Z") | endif
    if len(result) | call s:warn(result) | endif
  else
    echo "No vimux runner pane/window. Create one with VimuxOpenRunner"
  endif
endfunction

function! VimuxSendKeys(keys)
  if exists("g:VimuxRunnerIndex")
    let zoomed = _VimuxTmuxWindowZoomed()
    let result = _VimuxTmux((zoomed ? "resize-pane -Z \\; " : "" )
        \ ."send-keys -t ".g:VimuxRunnerIndex." -- ".a:keys)
    if zoomed | call _VimuxTmux("resize-pane -Z") | endif
    if len(result)
      call s:warn(result)
      return 1
    endif
  else
    echo "No vimux runner pane/window. Create one with VimuxOpenRunner"
  endif
endfunction

function! s:warn(msg)
  echohl WarningMsg
  redraw!
  try
    for line in split(a:msg, "\n")
      echomsg line
    endfor
  finally
    echohl None
  endtry
endfunction

function! VimuxOpenRunner()
  let nearestIndex = _VimuxNearestIndex()

  if !exists('g:VimuxRunnerIndex')
    if _VimuxOption("g:VimuxUseNearest", 1) == 1 && nearestIndex != -1
      let g:VimuxRunnerIndex = nearestIndex
    else
      if _VimuxRunnerType() == "pane"
        let height = _VimuxOption("g:VimuxHeight", 20)
        let orientation = _VimuxOption("g:VimuxOrientation", "v")
        call _VimuxTmux("split-window -p ".height." -".orientation)
      elseif _VimuxRunnerType() == "window"
        call _VimuxTmux("new-window")
      endif

      let g:VimuxRunnerIndex = _VimuxTmuxIndex()
      call _VimuxTmux("last-"._VimuxRunnerType())
    endif
  endif
endfunction

function! VimuxCloseRunner()
  if exists("g:VimuxRunnerIndex")
    call _VimuxTmux("kill-"._VimuxRunnerType()." -t ".g:VimuxRunnerIndex)
    unlet g:VimuxRunnerIndex
  endif
endfunction

function! VimuxTogglePane()
  if exists("g:VimuxRunnerIndex")
    if _VimuxRunnerType() == "window"
        call _VimuxTmux("join-pane -d -s ".g:VimuxRunnerIndex." -p "._VimuxOption("g:VimuxHeight", 20))
        let g:VimuxRunnerType = "pane"
    elseif _VimuxRunnerType() == "pane"
        let g:VimuxRunnerIndex=substitute(_VimuxTmux("break-pane -d -t ".g:VimuxRunnerIndex." -P -F '#{window_index}'"), "\n", "", "")
        let g:VimuxRunnerType = "window"
    endif
  endif
endfunction

function! VimuxZoomRunner()
  if exists("g:VimuxRunnerIndex")
    if _VimuxRunnerType() == "pane"
      if !_VimuxTmuxWindowZoomed()
        call _VimuxTmux("resize-pane -Z -t ".g:VimuxRunnerIndex)
      endif
    elseif _VimuxRunnerType() == "window"
      call _VimuxTmux("select-window -t ".g:VimuxRunnerIndex)
    endif
  endif
endfunction

function! VimuxInspectRunner()
  call _VimuxTmux("select-"._VimuxRunnerType()." -t ".g:VimuxRunnerIndex." \\; copy-mode")
endfunction

function! VimuxScrollUpInspect()
  call VimuxInspectRunner()
  call _VimuxTmux("last-"._VimuxRunnerType())
  call VimuxSendKeys("C-u")
endfunction

function! VimuxScrollDownInspect()
  call VimuxInspectRunner()
  call _VimuxTmux("last-"._VimuxRunnerType())
  call VimuxSendKeys("C-d")
endfunction

function! VimuxInterruptRunner()
  call VimuxSendKeys("^c")
endfunction

function! VimuxClearRunnerHistory()
  if exists("g:VimuxRunnerIndex")
    call _VimuxTmux("clear-history -t ".g:VimuxRunnerIndex)
  endif
endfunction

function! VimuxPromptCommand(...)
  let command = a:0 == 1 ? a:1 : ""
  let l:command = input(_VimuxOption("g:VimuxPromptString", "Command? "), command)
  if len(l:command)
    call VimuxRunCommand(l:command)
    let g:VimuxLastCommand = l:command
  endif
endfunction

function! _VimuxTmux(arguments)
  let l:command = _VimuxOption("g:VimuxTmuxCommand", "tmux")
  silent return system(l:command." ".a:arguments)
endfunction

function! _VimuxTmuxSession()
  return _VimuxTmuxProperty("#S")
endfunction

function! _VimuxTmuxIndex()
  if _VimuxRunnerType() == "pane"
    return _VimuxTmuxPaneIndex()
  else
    return _VimuxTmuxWindowIndex()
  end
endfunction

function! _VimuxTmuxPaneIndex()
  return _VimuxTmuxProperty("#I.#P")
endfunction

function! _VimuxTmuxWindowIndex()
  return _VimuxTmuxProperty("#I")
endfunction

function! _VimuxWindowPanes()
  return split(_VimuxTmux('list-panes -F "#{pane_id}"'), '\n')
endfunction

function! _VimuxTmuxWindowZoomed()
  if exists("g:VimuxRunnerType") && g:VimuxRunnerType !=# "pane"
    return 0
  elseif get(g:, 'VimuxRunnerIndex', '') =~# '^%\d\+$' &&
      \ index(_VimuxWindowPanes(), g:VimuxRunnerIndex) == -1
    return 0
  endif
  return _VimuxTmuxProperty("#F") =~# 'Z' && (
      \ !exists('g:VimuxRunnerIndex') || g:VimuxRunnerIndex !~ '\.' ||
      \ g:VimuxRunnerIndex =~# '^'._VimuxTmuxWindowIndex().'\.')
endfunction

function! _VimuxNearestIndex()
  let views = split(_VimuxTmux("list-"._VimuxRunnerType()."s"), "\n")

  for view in views
    if match(view, "(active)") == -1
      return split(view, ":")[0].(_VimuxRunnerType() == "pane" ? "" : ".")
    endif
  endfor

  return -1
endfunction

function! _VimuxRunnerType()
  return _VimuxOption("g:VimuxRunnerType", "pane")
endfunction

function! _VimuxOption(option, default)
  if exists(a:option)
    return eval(a:option)
  else
    return a:default
  endif
endfunction

function! _VimuxTmuxProperty(property)
    return substitute(_VimuxTmux("display -p '".a:property."'"), '\n$', '', '')
endfunction

function! _VimuxHasRunner(index)
  let runners = _VimuxTmux("list-"._VimuxRunnerType()."s -a")
  if stridx(a:index, '%') == -1
    return match(runners, a:index.":")
  else
    return match(runners, a:index)
  endif
endfunction
