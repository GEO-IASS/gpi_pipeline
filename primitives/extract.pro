;+
; NAME: extract
; PIPELINE PRIMITIVE DESCRIPTION: Assemble Datacube
;		
;		This is a wrapper routine to call either the spectral, polarized, or
;		undispersed extraction routines, depending on whichever is appropriate
;		for the current file. 
;
;		This routine transforms a 2D detector image in the dataset.currframe input
;		structure into a 2 or 3D data cube in the dataset.currframe output structure.
;
; INPUTS: detector image
; common needed: filter, wavcal, tilt, (nlens)
;
; KEYWORDS:
; GEM/GPI KEYWORDS:FILTER2
; DRP KEYWORDS:   
; OUTPUTS:
;
; PIPELINE COMMENT: Extract a 3D datacube from a 2D image (Calls assemble spectral or polarimetric cube automatically depending on input data format)
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="0"
; PIPELINE ORDER: 2.0
; PIPELINE TYPE: ALL
; PIPELINE SEQUENCE: 
;
; HISTORY:
;   2009-04-22 MDP: Created
;   2009-09-17 JM: added DRF parameters
;+
function extract, DataSet, Modules, Backbone
  common PIP
  COMMON APP_CONSTANTS

primitive_version= '$Id$' ; get version from subversion to store in header history
  @__start_primitive

  header=*(dataset.headers[numfile])
  mode=gpi_simplify_keyword_value(backbone->get_keyword('DISPERSR', count=c))
  ;if c eq 0 then mode=SXPAR( header, 'FILTER2', count=c)

  ; the return value will be the status flags OK/not_ok from
  ; whichever routine is actually executred...
  case strupcase(strc(mode)) of
  'PRISM':		return, extractcube(dataset, modules, backbone)
  'WOLLASTON':	return, extractpol(dataset, modules, backbone)
  'OPEN':	return, extractund(dataset, modules, backbone)
  else:
  endcase

end

