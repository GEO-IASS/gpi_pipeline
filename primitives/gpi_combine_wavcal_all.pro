;+
; NAME: gpi_combine_wavcal_all
; PIPELINE PRIMITIVE DESCRIPTION: Combine Wavelength Calibrations
;
; gpi_combine_wavcal_all is a simple median combination of wav. cal. files obtained with flat and arc images.
;  TO DO: exclude some mlens from the median in case of  wavcal 
;
; INPUTS: 3D wavcal 
;
; OUTPUTS:

; PIPELINE COMMENT: Combine wavelength calibration from  flat and arc
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="1" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="suffix" Type="string"  Default="-comb" Desc="Enter output suffix"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="2" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 4.2
; PIPELINE TYPE: CAL-SPEC
; PIPELINE SEQUENCE: 23-
;
; HISTORY:
;    Jerome Maire 2009-08-10
;   2009-09-17 JM: added DRF parameters
;-

function gpi_combine_wavcal_all,  DataSet, Modules, Backbone
@__start_primitive
	nfiles=dataset.validframecount

	if nfiles gt 1 then begin

		if tag_exist( Modules[thisModuleIndex], "Exclude") then Exclude= Modules[thisModuleIndex].exclude ;else exclude=

		sz=size(accumulate_getimage( dataset, 0))
		wavcalcomb=dblarr(sz[1],sz[2],sz[3])
	   
		header=*(dataset.headers)[numfile]
		filter = strcompress(sxpar( header ,'FILTER', count=fcount),/REMOVE_ALL)
		if fcount eq 0 then filter = strcompress(sxpar( header ,'FILTER1'),/REMOVE_ALL)
		cwv=get_cwv(filter)
		CommonWavVect=cwv.CommonWavVect
		lambda=cwv.lambda
	   
		lambdamin=commonwavvect[0]
		for wv=0,sz[3]-1 do begin
			wavcaltab=dblarr(sz[1],sz[2],nfiles)
			for n=0,nfiles-1 do begin
				wavcal =(accumulate_getimage( dataset, n))[*,*,*]
				wavcal = change_wavcal_lambdaref( wavcal, lambdamin)
				wavcaltab[*,*,n]=wavcal[*,*,wv]
			endfor
			wavcalcomb[*,*,wv]=median(wavcaltab,/double,dimension=3,/even)
		endfor
		*(dataset.currframe[0])=wavcalcomb

		basename=findcommonbasename(dataset.filenames[0:nfiles-1])
		FXADDPAR, *(DataSet.Headers[numfile]), 'DATAFILE', basename+'.fits'
		sxaddhist, functionname+": combined wavcal files:", *(dataset.headers[numfile])
		for i=0,nfiles do $ 
			sxaddhist, functionname+": "+strmid(dataset.filenames[i], 0,strlen(dataset.filenames[i])-6)+suffix+'.fits', *(dataset.headers[numfile])


		;suffix+='-comb'
	endif else begin
		sxaddhist, functionname+": Only one wavelength calibration supplied; nothing to combine!", *(dataset.headers[numfile])


	endelse
	 
@__end_primitive

end
