;+
; NAME: interpolate_badpix_2d
; PIPELINE PRIMITIVE DESCRIPTION: Interpolate bad pixels in 2D frame 
;
;	Interpolates between vertical (spectral dispersion) direction neighboring
;	pixels to fix each bad pixel.
;
;	TODO: need to evaluate whether that algorithm is still a good approach for
;	polarimetry mode files. 
;
;	TODO: implement Christian's suggestion of a 3D interpolation in 2D space,
;	using adjacent lenslet spectra as well. See emails of Oct 18, 2012
;	(excerpted below)
;
; KEYWORDS:
; 	gpitv=		session number for the GPITV window to display in.
; 				set to '0' for no display, or >=1 for a display.
;
; OUTPUTS:
;
; PIPELINE ARGUMENT: Name="CalibrationFile" type="badpix" default="AUTOMATIC" Desc="Filename of the desired bad pixel file to be read"
; PIPELINE ARGUMENT: Name="method" Type="string" Range="[nan|vertical|all8]" Default="vertical" Desc='Repair bad bix interpolating all 8 neighboring pixels, or just the 2 vertical ones, or just flag as NaN?'
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="1" Desc="1-500: choose gpitv session for displaying output, 0: no display "
;
; PIPELINE COMMENT:  Repair bad pixels by interpolating between their neighbors. Can optionally just flag as NaNs or else interpolate.
; PIPELINE ORDER: 1.1 
; PIPELINE TYPE: ALL HIDDEN
; PIPELINE NEWTYPE: SpectralScience,Calibration
;
;
; HISTORY:
; 	Originally by Marshall Perrin, 2012-10-18
; 	2012-12-03 MP: debugging/enhancements for the case of multiple adjacent bad
; 					pixels
; 	2012-12-09 MP: Added support for using information in DQ extension
;-
function interpolate_badpix_2d, DataSet, Modules, Backbone
primitive_version= '$Id$' ; get version from subversion to store in header history
calfiletype='badpix'
@__start_primitive


	sz = size( *(dataset.currframe) )
    if sz[1] ne 2048 or sz[2] ne 2048 then begin
        backbone->Log, "Image is not 2048x2048, don't know how to handle this for interpolating"
        return, NOT_OK
    endif


	if ~file_test( c_File) then return, error("Bad pixel file does not exist!")
    bpmask= gpi_READFITS(c_File)

    backbone->set_keyword,'HISTORY',functionname+": Loaded bad pixel map",ext_num=0
    backbone->set_keyword,'HISTORY',functionname+": "+c_File,ext_num=0
    backbone->set_keyword,'DRPBADPX',c_File,ext_num=0

	if tag_exist( Modules[thisModuleIndex], "method") then method=(Modules[thisModuleIndex].method) else method='vertical'


	if ptr_valid( dataset.currDQ) then begin
		; we have a DQ image provided by the detector server, so let's use it. 
		; DQ bit mask:
		;   0 = bad pixel, do not use if set
		;   1 = raw value was saturated
		;   2 = pixel diff between consecutive frames exceeds saturation
		;	3,4 = related to UTR calculations, do not indicated bad pixels
		; bits 0,1,2 = 7
		bpfromDQ = (*(dataset.currDQ) and 7) ne 0
		wbpfromDQ = where(bpfromDQ, bpfromDQcount)
		if bpfromDQcount gt 0 then begin
			bpmask[wbpfromDQ] = 1
			backbone->set_keyword, 'HISTORY', 'Found '+strc(bpfromDQcount)+' pixels marked as bad in DQ image FITS extension ', ext_num=0
		endif

	endif




	; MP (temporary?) fix for missed cold pixels: also repair anything super negative
	wlow = where(*dataset.currframe lt -50, lowct) ; should be an adjustible thresh, or based on read noise * n * sigma?
	if lowct gt 0 then begin
		backbone->set_keyword, 'HISTORY', 'Found '+strc(lowct)+' additional very negative pixels (< -50 cts) in that image. ', ext_num=0
		bpmask[wlow] = 1 ; 1 means bad in a bad pixel mask
	endif
	
	im0 = *dataset.currframe
	
	; don't bother trying to fix anything in the ref pix region
	bpmask[0:4,*] = 0
	bpmask[2043:2047,*] = 0
	bpmask[*,0:4] = 0
	bpmask[*,2043:2047] = 0

	
	wbad = where(bpmask, count)
	case strlowcase(method) of
	'nan': begin
		; just flag bad pixels as NaNs
		(*(dataset.currframe[0]))[wbad] = !values.f_nan
		backbone->set_keyword, 'HISTORY', 'Masking out '+strc(count)+' bad pixels to NaNs ', ext_num=0
		backbone->Log, 'Masking out '+strc(count)+' bad pixels and to NaNs'
	
	end

	'vertical': begin
		; Just uses neighboring pixels above and below

		; 1 row is 2048 pixels, so we can add or subtract 2048 to get to
		; adjacent rows
		;(*(dataset.currframe[0]))[wbad] =  ( (*(dataset.currframe[0]))[wbad+2048] + (*(dataset.currframe[0]))[wbad-2048]) / 2

		; The above simple method does **not** work, because it fails for the
		; case where a pixel's neighbors above and below are invalid. This is
		; true a *lot* of the time, due to the cross-shaped pattern around
		; hot pixels due to intrapixel capacitance.

		backbone->set_keyword, 'HISTORY', 'Masking out '+strc(count)+' bad pixels and replacing with interpolated values between vertical neighbors', ext_num=0
		backbone->Log, 'Masking out '+strc(count)+' bad pixels and replacing with interpolated values between vertical neighbors'

		; handle the easy cases in a vectorized fashion for major speedup:
		wvalid_above_and_below = where( (bpmask[wbad+2048] + bpmask[wbad-2048]) eq 0, ct_valid_above_and_below, complement=w_at_least_one_nbr_bad)
		wquickfix=wbad[wvalid_above_and_below]
		(*dataset.currframe)[wquickfix] =  ( (*dataset.currframe)[wquickfix+2048] + (*dataset.currframe)[wquickfix-2048]) / 2
		
		; now slog through the rest:
		wslowfix = wbad[w_at_least_one_nbr_bad]
		slowct =n_elements(wslowfix)

		for i=0,slowct-1 do begin
			statusline, "Fixing bad pixel "+strc(ct_valid_above_and_below +i) +" of "+strc(count)
			;if bpmask[wbad[i]+2048] eq 0 and bpmask[wbad[i]-2048] eq 0 then  begin
				;; both adjacent pixels above and below are good
				;(*dataset.currframe)[wbad] =  ( (*dataset.currframe)[wbad+2048] + (*dataset.currframe)[wbad-2048]) / 2
			;endif else 
			if bpmask[wslowfix[i]+2048] eq 0 then begin
				; adjacent above is only good one, just use that alone.
				 (*dataset.currframe)[wslowfix] =  (*dataset.currframe)[wslowfix+2048]
			endif else if  bpmask[wslowfix[i]-2048] eq 0 then begin
				; adjacent below is only good one, just use that alone
				(*dataset.currframe)[wslowfix] =  (*dataset.currframe)[wslowfix+2048]
			endif else begin
				; neither above nor below is valid. 
				; use average of whatever surrounding pixels are in fact valid
				whereis, bpmask, wslowfix[i], bx, by
				localvalid = 1-bpmask[bx-1:bx+1, by-1:by+1]
				localdata = (*dataset.currframe)[bx-1:bx+1, by-1:by+1]
				goodmean = total(localdata * localvalid) / total(localvalid)
				(*dataset.currframe)[wslowfix[i]] = goodmean
			endelse

		endfor

	end
	'all8': begin 
		; Uses all 8 neighboring pixels
		;

		; 1 row is 2048 pixels, so we can add or subtract 2048 to get to
		; adjacent rows
		(*(dataset.currframe[0]))[wbad] =  ( (*(dataset.currframe[0]))[wbad+2048-1:wbad+2048+1] + $
		 							 		 (*(dataset.currframe[0]))[wbad-2048-1:wbad-2048+1] + $
		 							 		 (*(dataset.currframe[0]))[wbad-1] + $
									 		 (*(dataset.currframe[0]))[wbad+1] ) / 8
		backbone->set_keyword, 'HISTORY', 'Masking out '+strc(count)+' bad pixels; replacing with interpolated values between each 8 neighbor pixels', ext_num=0
		backbone->Log, 'Masking out '+strc(count)+' bad pixels;  replacing with interpolated values between each 8 neighbor pixels'

	end
	'3D': begin
		stop
		;Let's say you have a bad pixel right at the middle of a spectrum. Instead of
		;taking the 2 vertical pixel neighbors, you take instead the values along the
		;spectrum and use also the information of surrounding spectra to help with the
		;interpolation (do a spatial and wavelength interpolation, but in the raw
		;detector plane ahead of the data cube extraction).
		;
		;
		;I like this idea. To expand on it a little bit, you would need to take each bad
		;pixel in the 2D array, and calculate which of the 40,000 lenslet spectra it's
		;closest to, using the wavelength solution. You'd end up with an (x,y) index for
		;the lenslet, a wavelength, and an offset from the spectrum midline in the cross
		;dispersion direction. 
		;
		;Then, you compute the adjacencies. You'd end up with 6 neighboring pixels:
		;  1 & 2: pixels in same lenslet spectrum at adjacent wavelengths. Immediate vertical neighboring pixels on the 2D array. 
		;  3,4,5,6: pixels at the same wavelength and cross-dispersion offset, for the 4 immediately adjacent lenslets. These pixels are offset on the detector by about 10 pixels in various diagonal directions. 
		;
		;So, then do you just take the average of all 6 of those? Or is there some more
		;clever way to interpolate in space and wavelength at once? 
		;
		;(In some small set of cases you'd have fewer than those 6, because you hit the
		;edge of the array or one of those other pixels is itself bad too. But that's a
		;tiny fraction of cases)
		;
	end

	endcase



	; update the DQ extension if it is present

	if ptr_valid( dataset.currDQ) then begin
		(*(dataset.currDQ))[wbad] = 0
		backbone->set_keyword,'HISTORY',functionname+": Updated DQ extension to indicate bad pixels were repaired.", ext_num=0
	endif



  suffix='-bpfix'


@__end_primitive
end

