;+
; NAME: set_calfile_type
; PIPELINE PRIMITIVE DESCRIPTION: Set Calibration Type
;
;
; INPUTS: datacube
;
;
; KEYWORDS:
; DRP KEYWORDS: FILETYPE,ISCALIB
;
; OUTPUTS:  
;
; PIPELINE COMMENT:  Set calibration type for recording a reduced calibration observation into the cal DB. 
; PIPELINE ARGUMENT: Name='filetype' type='string' Default='Dark' Desc="Calibration File Type"
; PIPELINE ARGUMENT: Name="save" Type="int" Range="[0,1]" Default="1" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="2" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 10.0
; PIPELINE TYPE: CAL/ALL
; PIPELINE NEWTYPE: Calibration
; PIPELINE SEQUENCE: 
;
; HISTORY:
; 	2011-08-01 MP: Updated for multi-extension FITS
;-  

function set_calfile_type, DataSet, Modules, Backbone
primitive_version= '$Id$' ; get version from subversion to store in header history
@__start_primitive

	if tag_exist( Modules[thisModuleIndex], "filetype") then if strc(Modules[thisModuleIndex].filetype) ne "" then filetype = string(Modules[thisModuleIndex].filetype)
	if filetype eq "" then begin
		message,"No file type specified!",/info
		return, not OK
	endif

;if numext eq 0 then begin
;	sxaddpar, *(dataset.headers[numfile]),  "FILETYPE", filetype, "What kind of IFS file is this?"
;	sxaddpar, *(dataset.headers[numfile]),  "ISCALIB", "YES", 'This is a reduced calibration file of some type.'
;endif else begin
;  sxaddpar, *(dataset.headersPHU[numfile]),  "FILETYPE", filetype, "What kind of IFS file is this?"
;  sxaddpar, *(dataset.headersPHU[numfile]),  "ISCALIB", "YES", 'This is a reduced calibration file of some type.'
;endelse
	backbone->set_keyword,  "FILETYPE", filetype, "What kind of IFS file is this?"
	backbone->set_keyword,  "ISCALIB", "YES", 'This is a reduced calibration file of some type.'

	save_suffix = strlowcase(strc(filetype)) ; or should the user specify this directly??
	suffix = strlowcase(strc(filetype)) ; or should the user specify this directly??

@__end_primitive
end
