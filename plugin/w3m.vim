"
" File: w3m.vim
" Author: yuratomo
" Last Modified: 2012.02.17
" Version: 0.0.1
" Usage: input :W3m [url or keyword]
"
" Setting:
"   highlight! link w3mLink StatusLineNC
"   highlight! link w3mInput String
"   highlight! link w3mSubmit Title
"
" Default Keymap:
"   <CR>      Open link under the cursor.
"   <TAB>     Move cursor next link.
"   <s-TAB>   Move cursor previous link.
"   <Space>   Scroll down.
"   <S-Space> Scroll up.
"   <BS>      Back page.
"   <A-LEFT>  Back page.
"   <A-RIGHT> Forward page.
"

if exists('g:loaded_w3m') && g:loaded_w3m == 1
  finish
endif

let s:save_cpo = &cpo
set cpo&vim

if !exists('g:w3m#command')
  let g:w3m#command = 'w3m'
endif
if !exists('g:w3m#option')
  let g:w3m#option = '-s -halfdump -o ext_halfdump=1 -o strict_iso2022=0 -o ucs_conv=1'
endif
if !exists('g:w3m#search_engin')
  let g:w3m#search_engin = 
    \ 'http://search.yahoo.co.jp/search?search.x=1&fr=top_ga1_sa_124&tid=top_ga1_sa_124&ei=SHIFT_JIS&aq=&oq=&p='
endif
if !exists('g:w3m#max_history_num')
  let g:w3m#max_history_num = 10
endif
if !exists('g:w3m#debug')
  let g:w3m#debug = 0
endif

let s:w3m_title = 'w3m'
let s:w3m_version = ''
let s:message_adjust = 20
let s:tmp_option = ''
let [s:TAG_START,s:TAG_END,s:TAG_BOTH,s:TAG_UNKNOWN] = range(4)

command! -nargs=* W3m :call w3m#Open(<f-args>)

function! w3m#Debug()
  setlocal modifiable

  let didx = len(b:display_lines)
  call setline(didx, '--------- tags --------')
  let didx += 1
  for dline in b:tag_list
    call setline(didx, 
      \ dline.line.",".
      \ dline.col.",".
      \ dline.type.",".
      \ dline.tagname.":".
      \ string(dline.attr))
    let didx += 1
  endfor
  call setline(didx, '--------- forms --------')
  let didx += 1
  for dline in b:form_list
    call setline(didx, 
      \ dline.line.",".
      \ dline.col.",".
      \ dline.type.",".
      \ dline.tagname.":".
      \ string(dline.attr))
    let didx += 1
  endfor
  call setline(didx, '--------- dbgmsg --------')
  let didx += 1
  call setline(didx, b:debug_msg)
  let didx += 1

  setlocal nomodifiable
endfunction
function! s:ddd(msg)
  if g:w3m#debug == 1 && exists('b:debug_msg')
    call add(b:debug_msg, a:msg)
  endif
endfunction

function! w3m#ShowUsage()
  echo "[Usage] :W3m url"
  echo "example :W3m http://www.google.co.jp"
endfunction

function! w3m#ShowURL()
    call s:message(b:last_url)
endfunction

function! w3m#Open(...)
  if len(a:000) == 0
    call w3m#ShowUsage()
    return
  endif

  call s:prepare_buffer()

  if s:isHttpURL(a:000[0])
    let url = s:normalizeUrl(a:000[0])
  else
    let url = g:w3m#search_engin . join(a:000, ' ')
  endif
  if len(b:url_history) - 1 > b:history_index
    call remove(b:url_history, b:history_index+1, -1)
    call remove(b:outputs_history, b:history_index+1, -1)
  endif
  let cols = winwidth(0) - &numberwidth
  let cmdline = join( [ g:w3m#command, s:tmp_option, g:w3m#option, '-cols', cols, '"' . url . '"' ], ' ')
  call add(b:url_history, url)
  call s:message( strpart('connect ' . cmdline, 0, cols - s:message_adjust) )
  call add(b:outputs_history, split(system(cmdline), '\n'))
  let b:history_index = len(b:url_history) - 1
  if b:history_index >= g:w3m#max_history_num
    call remove(b:url_history, 0, 0)
    call remove(b:outputs_history, 0, 0)
    let b:history_index = len(b:url_history) - 1
  endif

  call s:openCurrentHistory()
endfunction

function! w3m#Back()
  if b:history_index <= 0
    return
  endif
  let b:history_index -= 1
  call s:openCurrentHistory()
endfunction

function! w3m#Forward()
  if b:history_index >= len(b:url_history) - 1
    return
  endif
  let b:history_index += 1
  call s:openCurrentHistory()
endfunction

function! w3m#PrevLink()
  let [cl,cc] = [ line('.'), col('.') ]
  let tstart = -1
  let tidx = 0
  for tag in b:tag_list
    if tag.type == s:TAG_START && s:is_tag_tabstop(tag)
      if tag.line == cl && tag.col >= cc -1
        break
      elseif tag.line > cl
        break
      else
        let tstart = tidx
      endif
    endif
    let tidx = tidx + 1
  endfor
  if tstart != -1
    call cursor(b:tag_list[tstart].line, b:tag_list[tstart].col)
  endif
endfunction

function! w3m#NextLink()
  let [cl,cc] = [ line('.'), col('.') ]
  let tstart = -1
  let tidx = 0
  for tag in b:tag_list
    if tag.type == s:TAG_START && s:is_tag_tabstop(tag)
      if tag.line == cl && tag.col > cc
        let tstart = tidx
        break
      elseif tag.line > cl
        let tstart = tidx
        break
      endif
    endif
    let tidx = tidx + 1
  endfor
  if tstart != -1
    call cursor(b:tag_list[tstart].line, b:tag_list[tstart].col)
  endif
endfunction

function! w3m#Click()
  let [cl,cc] = [ line('.'), col('.') ]
  let tstart = -1
  let tidx = 0
  for tag in b:tag_list
    if tag.line == cl && tag.col > cc
      let tstart = tidx - 1
      break
    endif
    let tidx = tidx + 1
  endfor
  if tstart == -1
    call s:message('not process')
    return
  endif
  call s:message('processing')

  let tidx = tstart
  while tidx >= 0
    if b:tag_list[tidx].line != cl
      break
    endif
    if b:tag_list[tidx].type != s:TAG_START
      break
    endif
    let ret = s:dispatchTagProc(b:tag_list[tidx].tagname, tidx)
    if ret == 1
      break
    endif
    let tidx -= 1
  endwhile
  call s:message('done')
endfunction

function! s:post(url, file)
  let s:tmp_option = '-post ' . a:file
  call w3m#Open(a:url)
  let s:tmp_option = ''
  call s:message('post ok')
endfunction

function! s:openCurrentHistory()
  setlocal modifiable
  call s:message('analize output')
  let b:display_lines = s:analizeOutputs(b:outputs_history[b:history_index])
  let b:last_url = b:url_history[b:history_index]
  % delete _
  call setline(1, b:display_lines)
  call s:message('done')
  call s:applySyntax()
  setlocal bt=nofile noswf cursorline nomodifiable nowrap hidden listchars= 
endfunction

function! s:analizeOutputs(output_lines)
  let display_lines = []
  let b:tag_list = []
  let b:form_list = []

  let cline = 1
  for line in a:output_lines
    let analaized_line = ''
    let [lidx, ltidx, gtidx] = [ 0, -1, -1 ]
    while 1
      let ltidx = stridx(line, '<', lidx)
      if ltidx >= 0
        let analaized_line .= s:decordeEntRef(strpart(line, lidx, ltidx-lidx))
        let ccol = strlen(analaized_line) + 1
        let lidx = ltidx + 1
        let gtidx = stridx(line, '>', lidx)
        if gtidx >= 0
          let ctag = strpart(line, ltidx, gtidx-ltidx+1)
          let type = s:resolvTagType(ctag)
          let attr = {}
          let tname = s:analizeTag(ctag, attr)
          let item = {
              \ 'line':cline,
              \ 'col':ccol,
              \ 'type':type,
              \ 'tagname':tname,
              \ 'attr':attr,
              \ 'evalue':'',
              \ 'edited':0
              \ }
          call add(b:tag_list, item)
          if stridx(tname,'input') == 0
            call add(b:form_list, item)
          endif
          let lidx = gtidx + 1
        else
          let analaized_line .= s:decordeEntRef(strpart(line, lidx))
          break
        endif
      else
        let analaized_line .= s:decordeEntRef(strpart(line, lidx))
        break
      endif
    endwhile
    call add(display_lines, analaized_line)
    let cline += 1
  endfor
  return display_lines
endfunction

function! s:resolvTagType(tag)
  if stridx(a:tag, '<') == 0
    if stridx(a:tag, '/>') >= 0
      return s:TAG_BOTH
    elseif stridx(a:tag, '</') == 0
      return s:TAG_END
    else
      return s:TAG_START
    endif
  endif
  return s:TAG_UNKNOWN
endfunction

function! s:analizeTag(tag, attr)
  let tagname_e = stridx(a:tag, ' ') - 1
  if tagname_e < 0
    if a:tag[1:1] == '/'
      return strpart(a:tag, 2, strlen(a:tag)-3)
    else
      return strpart(a:tag, 1, strlen(a:tag)-2)
    endif
  endif

  let tagname = strpart(a:tag, 1, tagname_e)
  let idx = 0
  while 1
    " find start of value (vs)
    let vs = stridx(a:tag, '"', idx)
    if vs == -1
      break
    endif
    let vs += 1

    " find end of value (ve)
    let ve = stridx(a:tag, '"', vs)
    if ve == -1
      break
    endif
    let ve -= 1

    " find start of key (ks)
    let ks = strridx(a:tag, ' ', vs)
    if ks == -1
      break
    endif
    let ks += 1

    " find end of key (ke)
    let ke = stridx(a:tag, '=', ks)
    if ke == -1
      break
    endif
    let ke -= 1

    let a:attr[strpart(a:tag, ks, ke-ks+1)] = s:decordeEntRef(strpart(a:tag, vs, ve-vs+1))
    let idx = ve + 2
  endwhile

  return tagname
endfunction

function! s:prepare_buffer()
  if !exists('b:w3m_bufname')
    let id = 1
    while buflisted(s:w3m_title.'-'.id)
      let id += 1
    endwhile
    let bufname = s:w3m_title.'-'.id
    silent edit `=bufname`

    let b:w3m_bufname = s:w3m_title.'-'.id
    let b:last_url = ''
    let b:history_index = 0
    let b:url_history = []
    let b:outputs_history = []
    let b:display_lines = []
    let b:tag_list = []
    let b:form_list = []
    let b:debug_msg = []

    call s:keymap()
  endif
endfunction

function! s:keymap()
  if !exists('g:w3m#disable_default_keymap') || g:w3m#disable_default_keymap == 0
    nnoremap <buffer> <CR> :call w3m#Click()<CR>
    nnoremap <buffer> <TAB> :call w3m#NextLink()<CR>
    nnoremap <buffer> <s-TAB> :call w3m#PrevLink()<CR>
    nnoremap <buffer> <Space>   10<C-E>
    nnoremap <buffer> <S-Space> 10<C-Y>
    nnoremap <buffer> <BS> :call w3m#Back()<CR>
    nnoremap <buffer> <A-LEFT> :call w3m#Back()<CR>
    nnoremap <buffer> <A-RIGHT> :call w3m#Forward()<CR>
  endif
endfunction

function! s:applySyntax()
  try 
    syn clear w3mLink
  catch /.*/
  endtry

  let input_image_s = -1
  let link_s = -1
  for tag in b:tag_list
    if link_s == -1 && tag.tagname == 'a' && tag.type == s:TAG_START
      let link_s = tag.col
    elseif link_s != -1 && tag.tagname == 'a' && tag.type == s:TAG_END
      let link = s:escapeSyntax(strpart(getline(tag.line), link_s-1, tag.col-link_s))
      if strlen(link) > 1
        exe 'syn match w3mLink "' . link . '"'
      else
        exe 'syn match w3mLink "\<' . link . '\>"'
      endif
      "call s:ddd("highligh(l)!! " . link)
      let link_s = -1
    elseif input_image_s == -1 && s:is_tag_input_image_submit(tag) && tag.type == s:TAG_START
      let input_image_s = tag.col
    elseif input_image_s != -1 && stridx(tag.tagname, 'input') == 0 && tag.type == s:TAG_END
      let input_image_submit = s:escapeSyntax(strpart(getline(tag.line), input_image_s-1, tag.col-input_image_s))
      if strlen(input_image_submit) > 1
        exe 'syn match w3mSubmit "' . input_image_submit . '"'
      else
        exe 'syn match w3mSubmit "\<' . input_image_submit . '\>"'
      endif
      "call s:ddd("highligh(s)!! " . input_image_submit)
      let input_image_s = -1
    endif
  endfor

  syn region w3mInput start='\[' end='\]'
endfunction

function! s:escapeSyntax(str)
  return escape(a:str, '"\|*-[]')
endfunction

function! s:dispatchTagProc(tagname, tidx)
  if a:tagname == 'a'
    return s:tag_a(a:tidx)
  elseif stridx(a:tagname, 'input') == 0
    return s:tag_input(a:tidx)
  endif
  return 0
endfunction

function! s:tag_a(tidx)
  if has_key(b:tag_list[a:tidx].attr,'href')
    let url = s:resolveUrl(b:tag_list[a:tidx].attr.href)
    call w3m#Open(url)
  endif
  return 1
endfunction

function! s:tag_input(tidx)
  let url = ''
  " find form
  if !has_key(b:tag_list[a:tidx].attr,'type')
    return
  endif
  let type = b:tag_list[a:tidx].attr.type

  try 
    call s:tag_input_{tolower(type)}(a:tidx)
  catch /^Vim\%((\a\+)\)\=:E117/
  endtry

  return 1
endfunction

function! s:tag_input_image(tidx)
  if has_key(b:tag_list[a:tidx].attr,'value') && b:tag_list[a:tidx].attr.value ==? 'submit'
    call s:tag_input_submit(a:tidx)
  endif
endfunction

function! s:tag_input_submit(tidx)
    let idx = a:tidx - 1
    let action = 'GET'
    while idx >= 0
      if b:tag_list[idx].type == s:TAG_START && stridx(b:tag_list[idx].tagname, 'form') == 0
       if has_key(b:tag_list[idx].attr,'action') 
         let url = s:resolveUrl(b:tag_list[idx].attr.action)
         if has_key(b:tag_list[idx].attr,'method') 
           let action = b:tag_list[idx].attr.method
         endif
         break
       endif
     endif
     let idx -= 1
    endwhile

    "call s:ddd(action . ':' . url)
    if url != ''
      if action ==? 'GET'
        let query = s:buildQueryString()
        call w3m#Open(url . query)
      elseif action ==? 'POST'
        let file = s:generatePostFile()
        call s:post(url, file)
        call delete(file)
      else
        call s:message(toupper(action) . ' is not support')
      endif
    endif
endfunction

function! s:tag_input_text(tidx)
    redraw
    if b:tag_list[a:tidx].edited == 0
      if has_key(b:tag_list[a:tidx].attr, 'value')
        let value = b:tag_list[a:tidx].attr.value
      else
        let value = ''
      endif
    else
      let value = b:tag_list[a:tidx].evalue
    endif
    let b:tag_list[a:tidx].evalue = input('input:', value)
    let b:tag_list[a:tidx].edited = 1
    call s:applyEditedInputValues()
endfunction

function! s:tag_input_textarea(tidx)
  call s:tag_input_text(a:tidx)
endfunction

function! s:tag_input_password(tidx)
    redraw
    if b:tag_list[a:tidx].edited == 0
      let value = b:tag_list[a:tidx].attr.value
    else
      let value = b:tag_list[a:tidx].evalue
    endif
    let b:tag_list[a:tidx].evalue = input('input password:', value)
    let b:tag_list[a:tidx].edited = 1
    call s:applyEditedInputValues()
endfunction

function! s:tag_input_reset(tidx)
  for item in b:form_list
    if s:is_editable_tag(item)
      let item.evalue = ''
      let item.edited = 0
    endif
  endfor
  call s:applyEditedInputValues()
  call s:message('reset form data')
endfunction

"function! s:tag_input_xxx(tidx)
"endfunction

function! s:resolveUrl(action)
  if s:isHttpURL(a:action)
    return s:decordeEntRef(a:action)
  else
    let base = strridx(b:last_url, '/')
    let url = strpart(b:last_url, 0, base+1)
    return url . s:decordeEntRef(a:action)
  endif
endfunction

function! s:buildQueryString()
  let query = ''
  let first = 1
  for item in b:form_list
    if has_key(item.attr,'name') && has_key(item.attr,'value') && item.attr.name != ''
      if first == 1
        let query .= '?'
        let first = 0
      else
        let query .= '&'
      endif
      if item.edited == 0
        let value = item.attr.value
      else
        let value = item.evalue
      endif
      let query .= item.attr.name . '=' . s:encodeUrl(value)
    endif
  endfor
  "call s:ddd("query!! " . query)
  return query
endfunction

function! s:generatePostFile()
  let tmp_file = tempname()
  let items = []

  for item in b:form_list
    if has_key(item.attr,'name') && has_key(item.attr,'value') && item.attr.name != ''
      if item.edited == 0
        let value = item.attr.value
      else
        let value = item.evalue
      endif
      call add(items,  item.attr.name . '=' . s:encodeUrl(value))
    endif
  endfor

  call writefile(items, tmp_file)
  return tmp_file
endfunction

function! s:applyEditedInputValues()
  for item in b:form_list
    if s:is_editable_tag(item)
      if item.edited == 0
        if has_key(item.attr,'value')
          let value = item.attr.value
        else
          let value = ''
        endif
      else
        let value = item.evalue
      endif
      let line = getline(item.line)
      let s = stridx(line, '[')
      if s >= 0
        let e = stridx(line, ']')
        if e >= 0
          let s += strlen(value) + 1
          while s < e
            let value .= ' '
            let s += 1
          endwhile
        endif
      endif
      let line = strpart(line, 0, item.col-1) . value . strpart(line, item.col+strlen(value)-1)
      setlocal modifiable
      call setline(item.line, line)
      setlocal nomodifiable
    endif
  endfor
endfunction

function! s:encodeUrl(str)
  if &encoding == 'utf-8'
    let utf8str = a:str
  else
    let utf8str = iconv(a:str, &encoding, 'utf-8')
  endif
  let retval = substitute(utf8str,  '[^- *.0-9A-Za-z]', '\=s:ch2hex(submatch(0))', 'g')
  let retval = substitute(retval, ' ', '%20', 'g')
  return retval
endfunction

function! s:ch2hex(ch)
  let result = ''
  let i = 0
  while i < strlen(a:ch)
    let hex = s:nr2hex(char2nr(a:ch[i]))
    let result = result . '%' . (strlen(hex) < 2 ? '0' : '') . hex
    let i = i + 1
  endwhile
  return result
endfunction

function! s:nr2hex(nr)
  let n = a:nr
  let r = ""
  while 1
    let r = '0123456789ABCDEF'[n % 16] . r
    let n = n / 16
    if n == 0
      break
    endif
  endwhile
  return r
endfunction

function! s:isHttpURL(str)
  if stridx(a:str, 'http://') == 0 || stridx(a:str, 'https://') == 0
    return 1
  endif
  return 0
endfunction

function! s:normalizeUrl(url)
  let url = a:url
  let s1 = stridx(a:url, '/')
  let s2 = stridx(a:url, '/', s1+1)
  let s3 = stridx(a:url, '/', s2+1)
  if s3 == -1
    let url .= '/'
  endif
  return url
endfunction

function! s:decordeEntRef(str)
  let str = a:str
  let str = substitute(str, '&quot;',   '"', 'g')
  let str = substitute(str, '&#40;',    '(', 'g')
  let str = substitute(str, '&#41;',    ')', 'g')
  let str = substitute(str, '&laquo;',  '��', 'g')
  let str = substitute(str, '&raquo;',  '��', 'g')
  let str = substitute(str, '&lt;',     '<', 'g')
  let str = substitute(str, '&gt;',     '>', 'g')
  let str = substitute(str, '&amp;',    '\&','g')
  let str = substitute(str, '&yen;',    '\\','g')
  let str = substitute(str, '&cent;',   '��','g')
  let str = substitute(str, '&copy;',   'c', 'g')
  let str = substitute(str, '&middot;', '�E','g')
  let str = substitute(str, '&apos;',   "'", 'g')
  return    substitute(str, '&nbsp;',   ' ', 'g')
endfunction

function! s:message(msg)
  redraw
  if a:msg != ''
    echom 'w3m: ' . a:msg
  endif
endfunction

function! s:is_tag_input_image_submit(tag)
  if a:tag.tagname ==? 'input_alt'
    if has_key(a:tag.attr,'type') && a:tag.attr.type ==? 'image'
      if has_key(a:tag.attr,'value') && a:tag.attr.value ==? 'submit'
        return 1
      endif
    endif
  endif
  return 0
endfunction

function! s:is_editable_tag(tag)
  if has_key(a:tag.attr,'name') && has_key(a:tag.attr,'type') && a:tag.tagname ==? 'input_alt'
    if a:tag.attr.type ==? 'text' || a:tag.attr.type ==? 'textarea'
      return 1
    endif
  endif
  return 0
endfunction

function! s:is_tag_tabstop(tag)
  if a:tag.tagname ==? 'a' || a:tag.tagname ==? 'input_alt'
    return 1
  endif
  return 0
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo

let g:loaded_w3m = 1
