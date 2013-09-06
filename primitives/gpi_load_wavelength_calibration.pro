;+
; NAME: gpi_load_wavelength_calibration
; PIPELINE PRIMITIVE DESCRIPTION: Load Wavelength Calibration
;
; 	Reads a wavelength calibration file from disk.
; 	The wavelength calibration is stored using pointers into the common block.
;
; OUTPUTS: none; wavecal is loaded into memory
;
; PIPELINE COMMENT: Reads a wavelength calibration file from disk. This primitive is required for any data-cube extraction.
; PIPELINE ARGUMENT: Name="CalibrationFile" Type="wavcal" Default="AUTOMATIC" Desc="Filename of the desired wavelength calibration file to be read"
; PIPELINE ORDER: 0.5
; PIPELINE NEWTYPE: SpectralScience,Calibration
;
; HISTORY:
; 	Originally by Jerome Maire 2008-07
; 	Documentation updated - Marshall Perrin, 2009-04
;   2009-09-02 JM: hist added in header
;   2009-09-17 JM: added DRF parameters
;   2010-03-15 JM: added automatic detection
;   2010-08-19 JM: fixed bug which created new pointer everytime this primitive was called
;   2010-10-19 JM: split HISTORY keyword if necessary
;   2013-03-28 JM: added manual shifts of the wavecal
;   2013-04		   manual shifts code moved to new update_shifts_for_flexure
;   2013-07-10 MP: Documentation update and code cleanup
;   2013-07-16 MP: Rename file for consistency
;-

function gpi_load_wavelength_calibration, DataSet, Modules, Backbone

primitive_version= '$Id$' ; get version from subversion to store in header history
calfiletype = 'wavecal'
@__start_primitive


    ;open the wavecal file. Save into common block variable.
    wavcal = gpi_readfits(c_File,header=Header)


    ;update header:
	backbone->set_keyword, "HISTORY", functionname+": get wav. calibration file",ext_num=0
	backbone->set_keyword, "HISTORY", functionname+": "+c_File,ext_num=0

	backbone->set_keyword, "DRPWVCLF", c_File, "DRP wavelength calibration file used.", ext_num=0

@__end_primitive 

end
