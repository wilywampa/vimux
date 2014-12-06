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
  if exists("g:VimuxRunnerIndex")
    call VimuxRunCommand(g:VimuxLastCommand)
  else
    echo "No last vimux command."
  endif
endfunction

function! VimuxRunCommand(command, ...)
  if !exists("g:VimuxRunnerIndex") || _VimuxHasRunner(g:VimuxRunnerIndex) == -1
    call VimuxOpenRunner()
  endif

  let l:autoreturn = 1
  if exists("a:1")
    let l:autoreturn = a:1
  endif

  let resetSequence = _VimuxOption("g:VimuxResetSequence", "q C-u")
  let g:VimuxLastCommand = a:command

  call VimuxSendKeys(resetSequence)
  call VimuxSendText(a:command)

  if l:autoreturn == 1
    call VimuxSendKeys("Enter")
  endif
endfunction

function! VimuxSendText(text)
  let text = substitute(a:text, ';$', ';;', '')
  let text = '"'.escape(text, '"$').'"'
  if exists("g:VimuxRunnerIndex")
    let zoomed = _VimuxTmuxWindowZoomed()
    silent call system("tmux "
        \ .(zoomed ? "resize-pane -Z \\; " : "" )
        \ ."send-keys -l -t ".g:VimuxRunnerIndex." -- ".text)
    silent if zoomed | call system("tmux resize-pane -Z") | endif
  else
    echo "No vimux runner pane/window. Create one with VimuxOpenRunner"
  endif
endfunction

function! VimuxSendKeys(keys)
  if exists("g:VimuxRunnerIndex")
    let zoomed = _VimuxTmuxWindowZoomed()
    silent call system("tmux "
        \ .(zoomed ? "resize-pane -Z \\; " : "" )
        \ ."send-keys -t ".g:VimuxRunnerIndex." -- ".a:keys)
    silent if zoomed | call system("tmux resize-pane -Z") | endif
  else
    echo "No vimux runner pane/window. Create one with VimuxOpenRunner"
  endif
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
        silent call system("tmux split-window -p ".height." -".orientation)
      elseif _VimuxRunnerType() == "window"
        silent call system("tmux new-window")
      endif

      let g:VimuxRunnerIndex = _VimuxTmuxIndex()
      silent call system("tmux last-"._VimuxRunnerType())
    endif
  endif
endfunction

function! VimuxCloseRunner()
  if exists("g:VimuxRunnerIndex")
    silent call system("tmux kill-"._VimuxRunnerType()." -t ".g:VimuxRunnerIndex)
    unlet g:VimuxRunnerIndex
  endif
endfunction

function! VimuxTogglePane()
  if exists("g:VimuxRunnerIndex")
    if _VimuxRunnerType() == "window"
        silent call system("tmux join-pane -d -s ".g:VimuxRunnerIndex." -p "._VimuxOption("g:VimuxHeight", 20))
        let g:VimuxRunnerType = "pane"
    elseif _VimuxRunnerType() == "pane"
		silent let g:VimuxRunnerIndex=substitute(system("tmux break-pane -d -t ".g:VimuxRunnerIndex." -P -F '#{window_index}'"), "\n", "", "")
        let g:VimuxRunnerType = "window"
    endif
  endif
endfunction

function! VimuxZoomRunner()
  if exists("g:VimuxRunnerIndex")
    if _VimuxRunnerType() == "pane"
      if !_VimuxTmuxWindowZoomed()
        silent call system("tmux resize-pane -Z -t ".g:VimuxRunnerIndex)
      endif
    elseif _VimuxRunnerType() == "window"
      silent call system("tmux select-window -t ".g:VimuxRunnerIndex)
    endif
  endif
endfunction

function! VimuxInspectRunner()
  silent call system("tmux select-"._VimuxRunnerType()." -t ".g:VimuxRunnerIndex
      \ ." \\; copy-mode")
endfunction

function! VimuxScrollUpInspect()
  call VimuxInspectRunner()
  silent call system("tmux last-"._VimuxRunnerType())
  call VimuxSendKeys("C-u")
endfunction

function! VimuxScrollDownInspect()
  call VimuxInspectRunner()
  silent call system("tmux last-"._VimuxRunnerType())
  call VimuxSendKeys("C-d")
endfunction

function! VimuxInterruptRunner()
  call VimuxSendKeys("^c")
endfunction

function! VimuxClearRunnerHistory()
  if exists("g:VimuxRunnerIndex")
    silent call system("tmux clear-history -t ".g:VimuxRunnerIndex)
  endif
endfunction

function! VimuxPromptCommand(...)
  let command = a:0 == 1 ? a:1 : ""
  let l:command = input(_VimuxOption("g:VimuxPromptString", "Command? "), command)
  if len(l:command) | call VimuxRunCommand(l:command) | endif
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

function! _VimuxTmuxWindowZoomed()
  return _VimuxTmuxProperty("#F") =~# 'Z'
endfunction

function! _VimuxNearestIndex()
  silent let views = split(system("tmux list-"._VimuxRunnerType()."s"), "\n")

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
    silent return substitute(system("tmux display -p '".a:property."'"), '\n$', '', '')
endfunction

function! _VimuxHasRunner(index)
  silent return match(system("tmux list-"._VimuxRunnerType()."s -a"), a:index.":")
endfunction
