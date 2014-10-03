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

    if index != -1
        let doc= javadoc.classes[index]
        return [
        \   'class ' . doc.name,
        \   '  extends ' . doc.superclass,
        \   '  implements ' . join(doc.interfaces, ', '),
        \   '',
        \] + split(doc.comment_text, '\.\zs')
    else
        throw printf("Sorry, no javadoc available for `%s'", a:query)
    endif
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

call ref#register_detection('java', 'java')

let &cpo= s:save_cpo
unlet s:save_cpo
