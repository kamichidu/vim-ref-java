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
let s:F= s:V.import('System.File')
let s:M= s:V.import('Vim.Message')
unlet s:V

let s:source= {
\   'name': 'java',
\}

let s:logging_enabled= get(g:, 'ref#java#enable_logging', 0)
" XXX: for debug
let s:logging_enabled= 1

let s:data_dir= get(g:, 'ref#java#data_dir', expand('~/.ref_java/data/'))
let s:work_dir= get(g:, 'ref#java#work_dir', expand('~/.ref_java/work/'))
let s:log_dir=  get(g:, 'ref#java#log_dir',  expand('~/.ref_java/logs/'))

let s:jsondoclet_jarpath= globpath(&runtimepath, 'bin/json-doclet-0.0.0-jar-with-dependencies.jar')

try
    call vimproc#version()
    let s:has_vimproc= 1
catch
    let s:has_vimproc= 0
endtry

let s:empty_json= ['{"classes":[]}']

"
" memo
" ---
" s:source.cache({name}) => equivalent to {cache}[{name}]
" s:source.cache({name}, {gather}) =>
" s:source.cache({name}, {gather}, {update}) =>
"

function! s:source.available()
    return executable('mvn')
endfunction

function! s:source.get_body(query)
    " create data
    let deps_javadoc= s:J.decode(join(self.cache(getcwd(), function('s:make_javadoc')), ''))
    let jdk_javadoc= s:J.decode(join(self.cache($JAVA_HOME, function('s:make_jdk_javadoc')), ''))

    let classes= jdk_javadoc.classes + deps_javadoc.classes

    let index= s:L.find_index(classes, "v:val.name ==# '" . a:query . "'")

    if index == -1
        throw printf("Sorry, no javadoc available for `%s'", a:query)
    endif

    let doc= classes[index]

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
    let body+= s:render_dom(s:H.parse('<html><body>' . doc.comment_text . '</body></html>'))
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
    let deps_javadoc= s:J.decode(join(self.cache(getcwd(), function('s:make_javadoc')), ''))
    let jdk_javadoc= s:J.decode(join(self.cache($JAVA_HOME, function('s:make_jdk_javadoc')), ''))

    let classes= jdk_javadoc.classes + deps_javadoc.classes

    return map(filter(classes, 'v:val.name =~ a:query'), 'v:val.name')
endfunction

function! ref#java#create_cache(java_home, target_dir)
    let save_cwd= getcwd()
    try
        execute 'lcd' a:target_dir

        if !filereadable('pom.xml')
            return []
        endif

        let temporary_dir= s:join_path(s:work_dir, 'dependencies/')

        call s:log(printf("Copy dependencies into `%s' using maven", temporary_dir))
        " mvn dependency:copy-dependencies -Dclassifier=sources -DoutputDirectory=./deps
        let output= s:systemlist(printf('mvn dependency:copy-dependencies -Dclassifier=sources -DoutputDirectory="%s"', temporary_dir))
        call s:log("Copyed dependencies with output:", output)

        let jars= split(globpath(temporary_dir, '*'), "\n")

        let filenames= []
        for jar in jars
            let filename= s:create_data(a:java_home, jar)
            if filereadable(filename)
                let filenames+= [filename]
            endif
        endfor
        return filenames
    finally
        execute 'lcd' save_cwd
    endtry
endfunction

function! ref#java#create_jdk_doc(java_home)
    if !filereadable(s:join_path(a:java_home, 'src.zip'))
        return []
    endif

    let filename= s:create_data(a:java_home, s:join_path(a:java_home, 'src.zip'))
    if filereadable(filename)
        return [filename]
    else
        return []
    endif
endfunction

function! s:create_data(java_home, jarpath)
    if !filereadable(a:jarpath)
        throw printf("ref-java: File not found `%s'", a:jarpath)
    endif

    call s:log('Start creating javadoc data')

    let sources_dir= s:join_path(s:work_dir, 'sources/')
    let json_dir= s:join_path(s:data_dir, 'json/')

    call s:log(printf("sources_dir=`%s'", sources_dir))
    call s:log(printf("json_dir=`%s'", json_dir))

    " delete and create directories
    if isdirectory(sources_dir)
        call s:log('Remove sources_dir')
        call s:F.rmdir(sources_dir, 'r')
    endif
    call s:log('Create sources_dir')
    call mkdir(sources_dir, 'p')
    if !isdirectory(json_dir)
        call s:log('Create json_dir')
        call mkdir(json_dir, 'p')
    endif

    let filename= s:escape(a:jarpath)

    " skip if already cached
    if filereadable(s:join_path(json_dir, filename))
        return s:join_path(json_dir, filename)
    endif

    call s:log(printf("Copy a jar file `%s' into sources_dir", a:jarpath))
    call s:F.copy(a:jarpath, s:join_path(sources_dir, 'target.jar'))

    let save_cwd= getcwd()
    try
        execute 'lcd' sources_dir

        call s:log("Extract jar file")
        let output= s:systemlist(printf('"%s" -xf "%s"', s:join_path(a:java_home, 'bin/jar'), 'target.jar'))
        call s:log("Finishing extracting jar file with output:", output)

        call s:log("Collect filenames in jar")
        let output= s:systemlist(printf('"%s" -tf "%s"', s:join_path(a:java_home, 'bin/jar'), 'target.jar'))
        call s:log("Finishing collecting filenames with output:", output)
        let files= filter(output, 'v:val =~# "\\.java$"')
        call s:log("Collected filenames:", files)

        call writefile(files, './ref_Java_files')

        " make javadoc as json
        call s:log("Generate javadoc")
        let output= s:systemlist(join([
        \   '"' . s:join_path(a:java_home, 'bin/javadoc') . '"',
        \   printf('-docletpath "%s"', s:jsondoclet_jarpath),
        \   '-doclet jp.michikusa.chitose.doclet.JsonDoclet',
        \   printf('-ofile "%s"', s:join_path(json_dir, filename)),
        \   '-J-Xmx512m',
        \   '@ref_Java_files',
        \]))
        call s:log("Finishing generating javadoc with output:", output)
        call s:log(printf("Generated javadoc as `%s'", filename))

        return s:join_path(json_dir, filename)
    finally
        execute 'lcd' save_cwd
    endtry
endfunction

function! s:escape(name)
    return substitute(a:name, '[:;*?"<>|/\\%]', '\=printf("%%%02x", char2nr(submatch(0)))', 'g')
endfunction

function! s:systemlist(expr, ...)
    let args= [a:expr] + (a:0 > 0 ? [a:1] : [])

    if s:has_vimproc
        return split(call('vimproc#system', args), "\n")
    else
        return split(call('system', args), "\n")
    endif
endfunction

function! s:make_javadoc(name)
    " a:name ==# getcwd()
    let filenames= ref#java#create_cache($JAVA_HOME, a:name)

    let merged= {'classes': []}
    for filename in filenames
        let doc= s:J.decode(join(readfile(filename), "\n"))
        let merged.classes+= doc.classes
    endfor
    return [s:J.encode(merged)]
endfunction

function! s:make_jdk_javadoc(name)
    " a:name ==# $JAVA_HOME
    let filenames= ref#java#create_jdk_doc(a:name)

    if !empty(filenames)
        return readfile(filenames[0])
    else
        return deepcopy(s:empty_json)
    endif
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

function! s:render_dom(dom)
    try
        let text= wwwrenderer#render_dom(a:dom)
    catch /^Vim/
        let text= a:dom.toString()
    endtry

    return s:L.flatten(map(split(text, "\n"), 's:wrap(v:val)'))
endfunction

function! s:wrap(text)
    let words= split(a:text, '\s\+')
    let lines= []
    let buf= []
    for word in words
        if strlen(join(buf + [word])) <= &columns
            let buf+= [word]
        else
            let lines+= [join(buf)]
            let buf= []
        endif
    endfor
    if !empty(buf)
        let lines+= [join(buf)]
    endif
    return lines
endfunction

function! s:join_path(parent, filename)
    let path= substitute(a:parent, '/\+$', '', '') . '/' . a:filename
    return tr(path, '\', '/')
endfunction

" log('message', ['format', 'arg'])
function! s:log(...)
    if !s:logging_enabled
        return
    endif
    if a:0 <= 0
        return
    endif

    if !isdirectory(s:log_dir)
        call mkdir(s:log_dir, 'p')
    endif

    let messages= []
    for format in a:000
        if type(format) == type([])
            let messages+= format
        else
            let messages+= [format]
        endif
        unlet format
    endfor
    let filename= s:join_path(s:log_dir, strftime('%Y-%m-%d') . '.log')
    let content= filereadable(filename) ? readfile(filename) : []

    call writefile(content + messages, filename)
endfunction

function! ref#java#define()
    return deepcopy(s:source)
endfunction

call ref#register_detection('java', 'java')

let &cpo= s:save_cpo
unlet s:save_cpo
