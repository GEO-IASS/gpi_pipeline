
;+
; NAME: Shift 2D Image
; PIPELINE PRIMITIVE DESCRIPTION: Shift 2D Image
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
; PIPELINE COMMENT: Shift 2D image, by integer or fractional pixel amounts.  Doesn't shift ref pixels. 
; PIPELINE ARGUMENT: Name="dx" Type="float" Range="[-10,10]" Default="0" Desc="shift amount in X direction"
; PIPELINE ARGUMENT: Name="dy" Type="float" Range="[-10,10]" Default="0" Desc="shift amount in Y direction"
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="0" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="0" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 1.99
; PIPELINE TYPE: ALL
; PIPELINE NEWTYPE: ALL
;
; HISTORY:
;   2012-12-18 MP: New primitive.
;
function shift_2d_image, DataSet, Modules, Backbone

primitive_version= '$Id: applydarkcorrection.pro 1078 2012-12-14 03:23:58Z mperrin $' ; get version from subversion to store in header history
@__start_primitive

	dx = Modules[thisModuleIndex].dx
	dy = Modules[thisModuleIndex].dy

	backbone->set_keyword,'DRP_DX',dx,ext_num=0
	backbone->set_keyword,'DRP_DY',dy,ext_num=0

	sz = size(*dataset.currframe)
	if (sz[1] ne 2048) or (sz[2] ne 2048) then begin
		return, error("Image is not 2048x2048. Don't know how to shift it appropriately to preserve ref pixel areas")
	endif

	if (dx eq fix(dx)) and (dy eq fix(dy)) then begin
		backbone->set_keyword,'HISTORY',functionname+": shifting image by INTEGER pixels ("+strc(dx)+","+strc(dy)+")",ext_num=0

		(*dataset.currframe)[4:2043, 4:2043] = shift(  (*dataset.currframe)[4:2043, 4:2043], dx, dy )

	endif else begin
		backbone->set_keyword,'HISTORY',functionname+": shifting image by FRACTIONAL pixels ("+strc(dx)+","+strc(dy)+")",ext_num=0

		(*dataset.currframe)[4:2043, 4:2043] = fftshift(  (*dataset.currframe)[4:2043, 4:2043], dx, dy )
	endelse 
	  
  	suffix = 'shifted'
@__end_primitive 


end
