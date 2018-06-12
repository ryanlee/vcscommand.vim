" vim600: set foldmethod=marker:
"
" SVN extension for VCSCommand.
"
" Version:       VCS development
" Maintainer:    Bob Hiestand <bob.hiestand@gmail.com>
" License:
" Copyright (c) 2007 Bob Hiestand
"
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to
" deal in the Software without restriction, including without limitation the
" rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
" sell copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
"
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
" FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
" IN THE SOFTWARE.
"
" Section: Documentation {{{1
"
" Options documentation: {{{2
"
" VCSCommandDSSExec
"   This variable specifies the DSS executable.  If not set, it defaults to
"   'dss' executed from the user's executable path.
"
" VCSCommandDSSDiffExt
"   This variable, if set, sets the external diff program used by Subversion.
"
" VCSCommandSVNDiffOpt
"   This variable, if set, determines the options passed to the svn diff
"   command (such as 'u', 'w', or 'b').

" Section: Plugin header {{{1

if exists('VCSCommandDisableAll')
	finish
endif

if v:version < 700
	echohl WarningMsg|echomsg 'VCSCommand requires at least VIM 7.0'|echohl None
	finish
endif

runtime plugin/vcscommand.vim

if !executable(VCSCommandGetOption('VCSCommandDSSExec', 'dssc'))
	" DSS is not installed
	finish
endif

let s:save_cpo=&cpo
set cpo&vim

" Section: Variable initialization {{{1

let s:dssFunctions = {}

" Section: Utility functions {{{1

" Function: s:Executable() {{{2
" Returns the executable used to invoke git suitable for use in a shell
" command.
function! s:Executable()
	return shellescape(VCSCommandGetOption('VCSCommandDSSExec', 'dssc'))
endfunction

" Function: s:DoCommand(cmd, cmdName, statusText, options) {{{2
" Wrapper to VCSCommandDoCommand to add the name of the DSS executable to the
" command argument.
function! s:DoCommand(cmd, cmdName, statusText, options)
	if VCSCommandGetVCSType(expand('%')) == 'DSS'
		let fullCmd = s:Executable() . ' ' . a:cmd
		return VCSCommandDoCommand(fullCmd, a:cmdName, a:statusText, a:options)
	else
		throw 'DSS VCSCommand plugin called on non-DSS item.'
	endif
endfunction

" Section: VCS function implementations {{{1

" Function: s:dssFunctions.Identify(buffer) {{{2
function! s:dssFunctions.Identify(buffer)
	"let fileName = resolve(bufname(a:buffer))
	" for wam/pi cache area, design sync always be links, so don't resolve
	let fileName = bufname(a:buffer)
	if isdirectory(fileName)
		let directoryName = fileName
	else
		let directoryName = fnamemodify(fileName, ':h')
	endif
	if strlen(directoryName) > 0
		let dssDir = directoryName . '/.SYNC'
	else
		let dssDir = '.SYNC'
	endif
	let type = getftype(dssDir)
	" echomsg "type(" . dssDir . ")={" . type . "}"
	if type == "link" || type=="dir"
		" echomsg "found " . dssDir
		return g:VCSCOMMAND_IDENTIFY_EXACT
	else
		return 0
	endif
endfunction

" Function: s:dssFunctions.Commit(argList) {{{2
function! s:dssFunctions.Commit(argList)
	let ftext = join(readfile(a:argList[0]),'\n')
	let resultBuffer = s:DoCommand('ci -new -comment "' . ftext . '"', 'commit', '', {})
	if resultBuffer == 0
		echomsg 'No commit needed.'
	endif
endfunction

" Function: s:dssFunctions.Delete() {{{2
function! s:dssFunctions.Delete(argList)
	return s:DoCommand(join(['retire '] + a:argList, ' '), 'delete', join(a:argList, ' '), {})
endfunction

" Function: s:dssFunctions.Diff(argList) {{{2
function! s:dssFunctions.Diff(argList)
	" echomsg "argList={"
	" for a in a:argList
	" 	echomsg a . ""
	" endfor
	" echomsg "}"
	
	" Pass-through
	let caption = join(a:argList, ' ')
	let revOptions = a:argList

	if len(a:argList) == 0
		let revOptions = ['-version Orig']
		let caption = ''
	elseif match(a:argList, '^-') == -1
		let caption = '(' . a:argList[0] . ' : ' . get(a:argList, 1, 'current') . ')'
		if len(a:argList) == 1
			let revOptions = ['-version ' . a:argList[0] ]
		elseif len(a:argList) == 2
			let revOptions = ['"<VCSCOMMANDFILE>;'. a:argList[0] . '" "<VCSCOMMANDFILE>;'. a:argList[1]. '"']
		endif
	endif

	let dssDiffExt = VCSCommandGetOption('VCSCommandDSSDiffExt', '')
	if dssDiffExt == ''
		let diffExt = []
	else
		let diffExt = ['--diff-cmd ' . dssDiffExt]
	endif

	let dssDiffOpt = VCSCommandGetOption('VCSCommandDSSDiffOpt', '')
	if dssDiffOpt == ''
		let diffOptions = []
	else
		let diffOptions = [dssDiffOpt]
	endif

	return s:DoCommand(join(['diff -unified'] + diffExt + diffOptions + revOptions), 'diff', caption, {})
endfunction
	" diff -standard -embed -white -output /tmp/vkE8UoC/21 <F> '<F>;Orig

" Function: s:dssFunctions._GetBufferInfo() {{{2
" Provides version control details for the current file.  Current version
" number and current repository version number are required to be returned by
" the vcscommand plugin.
" Returns: List of results:  [revision, repository, branch]

function! s:dssFunctions._GetBufferInfo()
	let originalBuffer = VCSCommandGetOriginalBuffer(bufnr('%'))
	let fileName = bufname(originalBuffer)
	let statusText = s:VCSCommandUtility.system(s:Executable() . ' ls -report D "' . fileName . '"')
	if(v:shell_error)
		return []
	endif

	" File not under SVN control.
	if statusText =~ '^?'
		return ['Unknown']
	endif

	let [flags, revision, repository] = matchlist(statusText, '^\(.\{9}\)\s*\(\d\+\)\s\+\(\d\+\)')[1:3]
	if revision == ''
		" Error
		return ['Unknown']
	elseif flags =~ '^A'
		return ['New', 'New']
	elseif flags =~ '*'
		return [revision, repository, '*']
	else
		return [revision, repository]
	endif
endfunction

" Function: s:dssFunctions.Info(argList) {{{2
function! s:dssFunctions.Info(argList)
	"return s:DoCommand(join(['info --non-interactive'] + a:argList, ' '), 'info', join(a:argList, ' '), {})
	return s:DoCommand(join(['ls -report verbose'] + a:argList, ' '), 'info', join(a:argList, ' '), {})
endfunction

" Function: s:dssFunctions.Log(argList) {{{2
function! s:dssFunctions.Log(argList)
	if len(a:argList) == 0
		let options = []
		let caption = ''
	elseif len(a:argList) <= 2 && match(a:argList, '^-') == -1
		let options = ['-lastversions ' . join(a:argList, ':')]
		let caption = options[0]
	else
		" Pass-through
		let options = a:argList
		let caption = join(a:argList, ' ')
	endif

	let resultBuffer = s:DoCommand(join(['vhistory ', ''] + options), 'log', caption, {'AsyncRun':1})
	return resultBuffer
endfunction

" Function: s:dssFunctions.Revert(argList) {{{2
function! s:dssFunctions.Revert(argList)
	return s:DoCommand(join(['co -share -force -rec'] + a:argList, ' '), 'revert', '', {})
endfunction

" Function: s:dssFunctions.Review(argList) {{{2
function! s:dssFunctions.Review(argList)
	if len(a:argList) == 0
		let versiontag = '(current)'
		let versionOption = ''
	else
		let versiontag = a:argList[0]
		let versionOption = ' -version ' . versiontag . ' '
	endif

	return s:DoCommand('populate ' . versionOption, 'review', versiontag, {})
endfunction

" Function: s:dssFunctions.Status(argList) {{{2
function! s:dssFunctions.Status(argList)
	let options = []
	if len(a:argList) == 0
		let options = a:argList
	endif
	return s:DoCommand(join(['ls -report status'] + options, ' '), 'status', join(options, ' '), {})
endfunction

" Function: s:dssFunctions.Update(argList) {{{2
function! s:dssFunctions.Update(argList)
	return s:DoCommand('pop -uni -share -ver Trunk:Latest -rec', 'update', '', {})
endfunction

" Function: s:dssFunctions.Unlock(argList) {{{2
function! s:dssFunctions.Unlock(argList) " forced checkout
	"return s:DoCommand(join(['cancel '] + a:argList, ' '), 'unlock', join(a:argList, ' '), {})
	return s:DoCommand(join(['co -uni -get -force -ver Trunk:Latest -rec'] + a:argList, ' '), 'unlock', join(a:argList, ' '), {})
endfunction

" Function: s:dssFunctions.Lock(argList) {{{2
function! s:dssFunctions.Lock(argList)
	"return s:DoCommand(join(['co -lock -nocomment'] + a:argList, ' '), 'lock', join(a:argList, ' '), {})
	return s:DoCommand(join(['co -uni -lock'] + a:argList, ' '), 'lock', join(a:argList, ' '), {})
endfunction

" Section: Plugin Registration {{{1
let s:VCSCommandUtility = VCSCommandRegisterModule('DSS', expand('<sfile>'), s:dssFunctions, [])

let &cpo = s:save_cpo
