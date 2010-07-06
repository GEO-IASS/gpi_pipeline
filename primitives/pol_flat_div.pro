;+
; NAME: pol_flat_div
; PIPELINE PRIMITIVE DESCRIPTION: Divide by Polarized Flat Field
;
; INPUTS: data-cube
;
; KEYWORDS:
;	/Save	set to 1 to save the output image to a disk file. 
;
; OUTPUTS:  datacube with slice flat-fielded
;
; PIPELINE COMMENT: Divides a 2-slice polarimetry file by a flat field.
; PIPELINE ARGUMENT: Name="CalibrationFile" Type="polflat" Default="GPI-polflat.fits" Desc="Filename of the desired wavelength calibration file to be read"
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="1" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="2" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 3.5
; PIPELINE TYPE: ALL/POL
; PIPELINE SEQUENCE: 11-
;
;
; HISTORY:
; 	2009-07-22: MDP created
;   2009-09-17 JM: added DRF parameters
;   2009-10-09 JM added gpitv display
;-

function pol_flat_div, DataSet, Modules, Backbone
primitive_version= '$Id$' ; get version from subversion to store in header history
calfiletype='flat'
@__start_primitive

	polflat = readfits(c_File)

	; error check sizes of arrays, etc. 
	if not array_equal( (size(*(dataset.currframe[0])))[1:3], (size(polflat))[1:3]) then $
		return, error('FAILURE ('+functionName+'): Supplied flat field and data cube files do not have the same dimensions')

	; update FITS header history
	sxaddhist, functionname+": dividing by flat", *(dataset.headers[numfile])
	sxaddhist, functionname+": "+c_File, *(dataset.headers[numfile])


	*(dataset.currframe[0]) /= polflat


    if tag_exist( Modules[thisModuleIndex], "Save") && tag_exist( Modules[thisModuleIndex], "suffix") then suffix+=Modules[thisModuleIndex].suffix
  
@__end_primitive
end
