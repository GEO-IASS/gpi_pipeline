;+
; NAME: gpi_expand_path
;
; 	Utility function for expanding paths:
; 	 - expands ~ and ~username on Unix/Mac boxes
; 	 - expands environment variables in general.
; 	 - convert path separators to correct one of / or \ for current operating
; 	   system.
;
; 	See also: gpi_shorten_path.pro
;
; USAGE:
;    fullpath = gpi_expand_path( "$GPI_DATA_ROOT/dir/filename.fits")
;
; INPUTS:
; 	inputpath	some string
; OUTPUTS:
; 	returns the path with the variables expanded
;
; INPUT KEYWORDS:
;	/notruncate	By default if you have a string with a variable
;				in the middle of a path which has an absolute
;				path in it, the first part of the path should be
;				truncated off. Sometimes you don't want this behavior,
;				in particular the call in gpidrfparser__define that
;				expands all variables in an entire DRF before
;				storing it in a FITS header history.
;	/recursion	Used internally by this function when calling itself
;				recursively. Not otherwise useful.
;
; OUTPUT KEYWORD:
; 	vars_expanded	returns a list of the variables expanded. 
;
;
; NOTE:
; 	There is also a 'recursion' keyword. This is used internally by the function
; 	to expand multiple variables, and should never be set directly by a user.
;
; HISTORY:
; 	Began 2010-01-13 17:01:07 by Marshall Perrin 
; 	2010-01-22: Added vars_expanded, some debugging & testing to verify. MP
; 	2011-08-01 MP: Algorithm fix to allow environment variables to be written
; 		as either $THIS, $(THIS), or ${THIS} and it will work in all cases.
;	2012-08-22 MP: Updated to work with new directory names set in ways other
;		than just environment variables (though those work still too)
;	2013-10-07 MP: improved handling for absolute path specs in the middle of
;					a string
;-


FUNCTION gpi_expand_path, inputpath, vars_expanded=vars_expanded, recursion=recursion, notruncate=notruncate

compile_opt defint32, strictarr, logical_predicate

if N_elements(inputpath) EQ 0 then return,''
if size(inputpath,/TNAME) ne 'STRING' then return,inputpath

; Check for environment variables
;  match any string starting with a $ and optionally enclosed in ()s or {}s
res = stregex(inputpath, '\$(([a-zA-Z_]+)|(\([a-zA-Z_]+\))|(\{[a-zA-Z_]+\}))', length=length)

if res ge 0 then begin
	varname = strmid(inputpath,res+1,length-1)
	;print, varname, length, res
	first_char = strmid(varname,0,1)
	if first_char eq '(' or first_char eq '{' then varname=strmid(varname,1,length-3)
	if ~(keyword_set(vars_expanded)) or ~(keyword_set(recursion)) then vars_expanded = [varname] else vars_expanded =[vars_expanded,varname]

	var_value = gpi_get_directory(varname) 
	; if we have a variable name starting with a / for absolute path, but
	; then there is stuff prior to that in the file spec, we should log
	; that confusing state but hand back a valid absolute path anyway.
	
	if strmid(var_value,0,1) eq '/' and strmid(inputpath,0,res) ne '' and ~(keyword_set(notruncate)) then begin
		message,/info, 'Encountered absolute path variable in the middle of a filename; discarding everything that came before.'
		expanded = gpi_get_directory(varname)+ strmid(inputpath,res+length)
	endif else begin
		expanded = strmid(inputpath,0,res)+ gpi_get_directory(varname)+ strmid(inputpath,res+length)
	endelse


	return, gpi_expand_path(expanded, vars_expanded=vars_expanded,/recursion) ; Recursion!
endif

; swap path delimiters as needed
; is it ok for Mac? -JM
; Yes, macs are unix for these purposes. -MP
case !version.os_family of
   'unix': inputpath = strepex(inputpath,'\\','/',/all)
   'Windows': inputpath = strepex(inputpath,'/','\\',/all)
endcase

; clean up any double delimiters
inputpath = strepex(inputpath, path_sep()+path_sep(), path_sep(), /all)

return, expand_tilde(inputpath) ; final step: clean up tildes. 

 

end
