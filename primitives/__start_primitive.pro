;+
; NAME:  __start_primitive
;
; This code is meant to be included at the START of a GPI primitive using 
; @__start_primitive
;
; it is **not** a full routine on its own!
;
; HISTORY:
; 	Began 2010-04-08 19:25:24 by Marshall Perrin 
;   2010-10-19 JM: split HISTORY keyword if necessary
;   2011-07-30 MP: Updated for multi-extension FITS
;-



; some common initialization of useful stuff:
	common PIP
	COMMON APP_CONSTANTS

	getmyname, functionname
	thisModuleIndex = Backbone->GetCurrentModuleIndex()

; record this primitive name AND its version in the header for traceability.
	if ~(keyword_set(primitive_version)) then primitive_version="unknown"
  backbone->set_keyword,'HISTORY', "Running "+functionname+"; version "+primitive_version, ext_num=0


; if appropriate, attempt to locate and verify a calibration file.
	if keyword_set(calfiletype) then begin

		c_File = (Modules[thisModuleIndex].CalibrationFile)

		if strmatch(c_File, 'AUTOMATIC',/fold) then begin
		    c_File = (Backbone_comm->Getgpicaldb())->get_best_cal_from_header( calfiletype, *(dataset.headersPHU)[numfile],*(dataset.headersExt)[numfile] ) 

			if size(c_file,/tname) eq 'INT' then if c_file eq NOT_OK then begin
				return, error('ERROR IN CALL ('+strtrim(functionName)+'): Calibration File could not be found in calibrations database.')
			endif else begin
;				sxaddhist, functionname+": Automatically resolved calibration file of type '"+calfiletype+"'.", *(dataset.headers[numfile])
;				sxaddhist, functionname+":   "+c_File , *(dataset.headers[numfile])
				fxaddpar,*(dataset.headersPHU[numfile]),'HISTORY',functionname+": Automatically resolved calibration file of type '"+calfiletype+"'."
				fxaddpar,*(dataset.headersPHU[numfile]),'HISTORY',functionname+":   "+c_File 
			endelse
		endif
		c_File = gpi_expand_path(c_File)  


		; in either case, does the requested file actually exist?
		if ( NOT file_test ( c_File ) ) then $
		   return, error ('ERROR IN CALL ('+strtrim(functionName)+'): Calibration File  ' + $
						  strtrim(string(c_File),2) + ' not found.' )

		; FIXME add some lines here to log the calibration filename to the
		; header automatically
	endif




