;+
; NAME: combine2Dframes
; PIPELINE PRIMITIVE DESCRIPTION: Combine 2D images
;
;  TODO: more advanced combination methods. Mean, sigclip, etc.
;
; INPUTS: 2D image from narrow band arclamp
; common needed:
;
; KEYWORDS:
; OUTPUTS:
;
; GEM/GPI KEYWORDS:
; DRP KEYWORDS: NAXIS1,NAXIS2
;
; PIPELINE COMMENT: Combine 2D images such as darks into a master file via mean or median. 
; PIPELINE ARGUMENT: Name="Method" Type="enum" Range="MEAN|MEDIAN|MEANCLIP"  Default="MEDIAN" Desc="How to combine images: median, mean, or mean with outlier rejection?"
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="1" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name='suffix' Type='string' Default='median' Desc="choose the suffix"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="2" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 1.41
; PIPELINE TYPE: ALL
; PIPELINE SEQUENCE: 22-

; HISTORY:
; 	 Jerome Maire 2008-10
;   2009-09-17 JM: added DRF parameters
;   2009-10-22 MDP: Created from mediancombine_darks, converted to use
;   				accumulator.
;   2010-01-25 MDP: Added support for multiple methods, MEAN method.
;   2011-07-30 MP: Updated for multi-extension FITS
;
;-
function combine2Dframes, DataSet, Modules, Backbone
primitive_version= '$Id$' ; get version from subversion to store in header history
@__start_primitive

	if tag_exist( Modules[thisModuleIndex], "suffix") then suffix=Modules[thisModuleIndex].suffix else suffix='median'
	if tag_exist( Modules[thisModuleIndex], "method") then method=Modules[thisModuleIndex].method else method='median'
	;header=*(dataset.headers[numfile])

	nfiles=dataset.validframecount

	; Load the first file so we can figure out their size, etc. 
	im0 = accumulate_getimage(dataset, 0, hdr,hdrext=hdrext)
	;imtab=dblarr(naxis(0),naxis(1),numfile)
	 ;if numext eq 0 then hdr0= hdr else hdr0= hdrext
	sz = [0, backbone->get_keyword('NAXIS1'), backbone->get_keyword('NAXIS2')]
	; create an array of the same type as the input file:
	imtab = make_array(sz[1], sz[2], nfiles, type=size(im0,/type))



	; read in all the images at once
	for i=0,nfiles-1 do imtab[*,*,i] =  accumulate_getimage(dataset,i,hdr,hdrext=hdrext)

	; now combine them.
	if nfiles gt 1 then begin
		;fxaddpar, *(dataset.headersPHU[numfile]), 'HISTORY', functionname+":   Combining n="+strc(nfiles)+' files using method='+method
		backbone->set_keyword,'HISTORY', functionname+":   Combining n="+strc(nfiles)+' files using method='+method,ext_num=0
		
		backbone->Log, "	Combining n="+strc(nfiles)+' files using method='+method
		case STRUPCASE(method) of
		'MEDIAN': begin 
			combined_im=median(imtab,/DOUBLE,DIMENSION=3) 
		end
		'MEAN': begin
			combined_im=total(imtab,/DOUBLE,3) /((size(imtab))[3])
		end
		'MEANCLIP': begin
			message, 'Method MEANCLIP not implemented yet - bug Marshall to program it!'
		end
		else: begin
			message,"Invalid combination method '"+method+"' in call to Combine 2D Frames."
			return, NOT_OK
		endelse
		endcase
	endif else begin

		;fxaddpar, *(dataset.headersPHU[numfile]), 'HISTORY', functionname+":   Only 1 file supplied, so nothing to combine."
		 backbone->set_keyword,'HISTORY', functionname+":   Only 1 file supplied, so nothing to combine.",ext_num=0
		
		message,/info, "Only one frame supplied - can't really combine it with anything..."

		combined_im = imtab[*,*,0]
	endelse


	 ;TODO header update
	 pos=strpos(filename,'-',/REVERSE_SEARCH)
	; writefits,strmid(filename,0,pos+1)+suffix+'.fits',im,h

	; store the output into the backbone datastruct
	*(dataset.currframe)=combined_im
	;*(dataset.headers[numfile]) = hdr0 ; NO!! DO NOT JUST REPLACE THIS HEADER - that screws up the 'DATAFILE' keyword used in
										; save_currdata for the filename.
	dataset.validframecount=1

@__end_primitive
end
