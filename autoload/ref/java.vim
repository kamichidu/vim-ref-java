" The MIT License (MIT)
"
" Copyright (c) 2014 kamichidu
"
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to deal
" in the Software without restriction, including without limitation the rights
" to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
" copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
"
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
" OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
" THE SOFTWARE.
let s:save_cpo= &cpo
set cpo&vim

let s:V= vital#of('ref_java')
let s:L= s:V.import('Data.List')
let s:J= s:V.import('Web.JSON')
let s:H= s:V.import('Web.HTML')
unlet s:V

let s:source= {
\   'name': 'java',
\}

"
" memo
" ---
" s:source.cache({name}) => equivalent to {cache}[{name}]
" s:source.cache({name}, {gather}) =>
" s:source.cache({name}, {gather}, {update}) =>
"

function! s:source.available()
    return 1
endfunction

function! s:source.get_body(query)
    " create data
    let javadoc= s:J.decode(join(self.cache('javadoc', function('s:make_javadoc')), ''))

    let index= s:L.find_index(javadoc.classes, "v:val.name ==# '" . a:query . "'")

    if index == -1
        throw printf("Sorry, no javadoc available for `%s'", a:query)
    endif

    let doc= javadoc.classes[index]

    let body= ['class ' . doc.name]
    if !empty(doc.superclass)
        let body+= ['    extends ' . doc.superclass]
    endif
    if !empty(doc.interfaces)
        let body+= ['    implements ' . join(doc.interfaces, ', ')]
    endif
    let body+= ['']
    let body+= ['since ' . doc.since]
    if !empty(doc.see)
        let body+= ['see  ' . join(doc.see, ', ')]
    endif
    let body+= ['']
    let body+= [wwwrenderer#render_dom(s:H.parse('<html><body>' . doc.comment_text . '</body></html>'))]
    let body+= ['']
    let body+= ['Fields']
    if !empty(doc.fields)
        let body+= s:shift_indent(map(copy(doc.fields), 's:format_field(v:val)'))
    endif
    let body+= ['Constructors']
    if !empty(doc.constructors)
        let body+= s:shift_indent(map(copy(doc.constructors), 's:format_method(v:val)'))
    endif
    let body+= ['Methods']
    if !empty(doc.methods)
        let body+= s:shift_indent(map(copy(doc.methods), 's:format_method(v:val)'))
    endif
    return body
endfunction

function! s:source.get_keyword()
    return ref#get_text_on_cursor()
endfunction

function! s:source.complete(query)
    " create data
    let javadoc= s:J.decode(join(self.cache('javadoc', function('s:make_javadoc')), ''))

    return map(filter(javadoc.classes, 'v:val.name =~ a:query'), 'v:val.name')
endfunction

function! ref#java#define()
    return deepcopy(s:source)
endfunction

function! s:make_javadoc(name)
    let json_filename= globpath(&runtimepath, 'jdk1.7.0_40.jsondoc')

    return readfile(json_filename)
endfunction

function! s:format_field(doc)
    " {type} {field}
    return a:doc.type . ' ' . a:doc.name
endfunction

function! s:format_method(doc)
    " [{return}] {method}({parameters}) [throws {throws}]
    let desc= []

    if has_key(a:doc, 'return_type')
        let desc+= [a:doc.return_type, ' ']
    endif

    let desc+= [
    \   a:doc.name,
    \   '(',
    \   join(map(copy(a:doc.parameters), 'v:val.type . " " . v:val.name'), ', '),
    \   ')',
    \]

    if !empty(a:doc.throws)
        let desc+= [
        \   ' ',
        \   'throws',
        \   ' ',
        \   join(a:doc.throws, ', '),
        \]
    endif

    return join(desc, '')
endfunction

function! s:shift_indent(lines)
    return map(copy(a:lines), '"    " . v:val')
endfunction

call ref#register_detection('java', 'java')

let &cpo= s:save_cpo
unlet s:save_cpo
