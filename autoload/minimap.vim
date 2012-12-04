" vim:set ts=8 sts=2 sw=2 tw=0 et nowrap:
"
" minimap.vim - Autoload of minimap plugin for Vim.
"
" License: THE VIM LICENSE
"
" Copyright:
"   - (C) 2012 MURAOKA Taro (koron.kaoriya@gmail.com)

scriptencoding utf-8

let s:minimap_id = 'MINIMAP'
let s:minimap_mode = get(s:, 'minimap_mode', 0)

function! minimap#_is_open(id)
  let servers = split(serverlist(), '\n', 0)
  return len(filter(servers, 'v:val ==? a:id')) > 0 ? 1 : 0
endfunction

function! minimap#_open(id, ack)
  if has('gui_macvim')
    call minimap#_open_macvim(a:id, a:ack)
  else
    call minimap#_open_others(a:id, a:ack)
  endif
endfunction

function! minimap#_open_macvim(id, ack)
  let macvim_dir = $VIM . '/../../../..'
  let cmd_args = [
        \ macvim_dir . '/MacVim.app/Contents/MacOS/Vim',
        \ '-g',
        \ '--servername', a:id,
        \ '-c', printf("\"let g:minimap_ack=\'%s\'\"", a:ack),
        \ ]
  silent execute '!'.join(cmd_args, ' ')
endfunction

function! minimap#_open_others(id, ack)
  let args = [
        \ 'gvim',
        \ '--servername', a:id,
        \ '-c', printf("\"let g:minimap_ack=\'%s\'\"", a:ack),
        \ ]
  silent execute '!start '.join(args, ' ')
endfunction

function! minimap#_send(id)
  let data = { 
        \ 'sender': v:servername,
        \ 'path': minimap#_get_current_path(),
        \ 'line': line('.'),
        \ 'col': col('.'),
        \ 'start': line('w0'),
        \ 'end': line('w$'),
        \ }
  call remote_expr(a:id, 'minimap#_on_recv("' . string(data) . '")')
endfunction

function! minimap#_on_open()
  " setup view parameters.
  call minimap#_set_small_font()
  set guioptions= laststatus=0 cmdheight=1 nowrap
  set columns=80 foldcolumn=0
  set scrolloff=0
  set cursorline
  hi clear CursorLine
  hi link CursorLine Cursor
  winpos 0 0
  set lines=999

  " send ACK for open.
  if exists('g:minimap_ack')
    let expr = printf(':call minimap#_ack_open("%s")<CR>', v:servername)
    call remote_send(g:minimap_ack, expr)
    unlet g:minimap_ack
  endif
endfunction

function! minimap#_set_small_font()
  if has('gui_macvim')
    set noantialias
    set guifont=Osaka-Mono:h3
  elseif has('gui_win32')
    set guifont=MS_Gothic:h3:cSHIFTJIS
  else
    " TODO: for other platforms.
  endif
endfunction

function! minimap#_get_current_path()
  return substitute(expand('%:p'), '\\', '/', 'g')
endfunction

function! minimap#_on_recv(data)
  let data = eval(a:data)
  let path = data['path']
  if len(path) == 0
    return
  endif
  if path !=# minimap#_get_current_path()
    execute 'view! ' . path
  endif
  if path ==# minimap#_get_current_path()
    call minimap#_set_view_range(data['line'], data['col'],
          \ data['start'], data['end'])
  endif
endfunction

function! minimap#_set_view_range(line, col, start, end)
  " ensure to show view range.
  if a:start < line('w0')
    silent execute printf('normal! %dGzt', a:start)
  endif
  if a:end > line('w$')
    silent execute printf('normal! %dGzb', a:end)
  endif
  " mark view range.
  let p1 = printf('\%%>%dl\%%<%dl', a:start - 1, a:line)
  let p2 = printf('\%%>%dl\%%<%dl', a:line, a:end + 1)
  silent execute printf('match Search /\(%s\|%s\).*/', p1, p2)
  " move cursor
  call cursor(a:line, a:col)
  " redraw
  call minimap#_redraw()
endfunction

let s:last_redraw_time = [0, 0]

function! minimap#_redraw()
  let now = reltime()
  let diff = [now[0] - s:last_redraw_time[0], now[1] - s:last_redraw_time[1]]
  " inhibit to redraw in 100msec after last redraw.
  if diff[0] == 0 && diff[1] < 100000
    return
  endif
  " delay redraw by feedkeys()
  let s:last_redraw_time = now
  call feedkeys(":redraw\<CR>", 'n')
endfunction

function! minimap#_set_autosync()
  let s:minimap_mode = 1
  augroup minimap_auto
    autocmd!
    autocmd CursorMoved * call minimap#_sync()
  augroup END
endfunction

function! minimap#_unset_autosync()
  let s:minimap_mode = 0
  augroup minimap_auto
    autocmd!
  augroup END
endfunction

function! minimap#_send_and_enter_minimap_mode(id)
  call minimap#_send(a:id)
  if s:minimap_mode == 0
    call minimap#_enter_minimap_mode()
  endif
endfunction

function! minimap#_sync()
  let id = s:minimap_id
  if minimap#_is_open(id) == 0
    call minimap#_open(id, v:servername)
  else
    call minimap#_send_and_enter_minimap_mode(id)
  endif
endfunction

function! minimap#_ack_open(id)
  call foreground()
  call minimap#_send_and_enter_minimap_mode(a:id)
endfunction

function! minimap#_delete_command(cmd)
  if exists(':' . a:cmd)
    execute 'delcommand ' . a:cmd
  endif
endfunction

function! minimap#_enter_minimap_mode()
  call minimap#_set_autosync()
  call minimap#_delete_command('MinimapSync')
  command! MinimapStop call minimap#_leave_minimap_mode()
endfunction

function! minimap#_leave_minimap_mode()
  call minimap#_unset_autosync()
  call minimap#_delete_command('MinimapStop')
  command! MinimapSync call minimap#_sync()
endfunction

function! minimap#init()
  if v:servername =~? s:minimap_id
    call minimap#_on_open()
  else
    command! MinimapSync call minimap#_sync()
  endif
endfunction
