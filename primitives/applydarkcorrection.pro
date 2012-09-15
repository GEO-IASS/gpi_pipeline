
;+
; NAME: ApplyDarkCorrection
; PIPELINE PRIMITIVE DESCRIPTION: Subtract Dark/Sky Background
;
;
; INPUTS: 
;
; KEYWORDS:
; 	CalibrationFile=	Name of dark file to subtract.
;
; OUTPUTS: 
; 	2D image corrected
;
; ALGORITHM TODO: Deal with uncertainty and pixel mask frames too.
;
; PIPELINE COMMENT: Subtract a dark frame. 
; PIPELINE ARGUMENT: Name="CalibrationFile" Type="dark" Default="AUTOMATIC"
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="0" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="0" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 1.26
; PIPELINE TYPE: ALL
; PIPELINE NEWTYPE: ALL
;
; HISTORY:
; 	Originally by Jerome Maire 2008-06
; 	2009-04-20 MDP: Updated to pipeline format, added docs. 
; 				    Some code lifted from OSIRIS subtradark_000.pro
;   2009-09-02 JM: hist added in header
;   2009-09-17 JM: added DRF parameters
;   2010-10-19 JM: split HISTORY keyword if necessary
;   2012-07-20 MP: added DRPDARK keyword
;
function ApplyDarkCorrection, DataSet, Modules, Backbone

primitive_version= '$Id$' ; get version from subversion to store in header history
calfiletype = 'dark'
@__start_primitive

  ;fits_info, c_File, /silent, N_ext=n_ext
  ;if n_ext eq 0 then dark=readfits(c_File) else dark=mrdfits(c_File,1)
	dark = gpi_readfits(c_File)
  
	;dark=readfits(c_File)
    ;before = *(dataset.currframe[0])
	*(dataset.currframe[0]) -= dark
    ;after =*(dataset.currframe[0])

    ;atv, [[[before]],[[dark]],[[after]]],/bl
    ;stop
  	backbone->set_keyword,'HISTORY',functionname+": dark subtracted using file=",ext_num=0
  	backbone->set_keyword,'HISTORY',functionname+": "+c_File,ext_num=0
  	backbone->set_keyword,'DRPDARK',c_File,ext_num=0
  
	thisModuleIndex = Backbone->GetCurrentModuleIndex()
  	if tag_exist( Modules[thisModuleIndex], "Save") && tag_exist( Modules[thisModuleIndex], "suffix") then suffix+=Modules[thisModuleIndex].suffix
  

  	suffix = 'darksub'
@__end_primitive 


end
