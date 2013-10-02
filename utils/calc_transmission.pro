function calc_transmission, filter, pupil_mask_string, lyot_mask_string, without_filter=without_filter, resolution=resolution
; this determines the transmission of the instrument for a given setup
; it also outputs the default resolution of a spectrum for a given band

; the nominal transmission of 18.6% is the transmission at 1.55um and
; assumes the H-band PPM, the 080m12_04 Lyot and the H-band filter.
; this transmission value was measured for the ATP testing (REQ-FPR-0210)

; if the without_filter keyword is set, it returns the transmission WITHOUT accounting for the filter transmission!
; Otherwise, it assumes the transmission for a given filter is that of the central wavelength of that filter
; (found in the pipeline/config/pipeline_constants.txt file)

compile_opt defint32, strictarr, logical_predicate

	transmission=0.186

	; normalized to H-band Lyot - 080m12_04 
	lyot_trans=0.8102486d0 ; for  080m12_04 

	case lyot_mask_string of
	'LYOT_OPEN_G6231': lyot_correction=(1.0/lyot_trans)
	'080m12_02': lyot_correction=(0.8557484/lyot_trans)
	'080m12_03': lyot_correction=(0.8323324/lyot_trans)
	'080m12_04': lyot_correction=(0.8102486/lyot_trans)
	'080m12_04_c': lyot_correction=(0.7773553/lyot_trans)
	'080m12_06': lyot_correction=(0.7629011/lyot_trans)
	'080m12_06_03': lyot_correction=(0.7781433/lyot_trans)
	'080m12_07': lyot_correction=(0.7520283/lyot_trans)
	'080m12_10': lyot_correction=(0.6220372/lyot_trans)
	;else: return, error('FAILURE (calc_transmission): No throughput defined for the given Lyot Stop')
	else: begin 
		message,'No throughput defined for the given Lyot stop '+lyot_mask_string+'. Choices are LYOT_OPEN_G6231, 080m12_02, 080m12_03, 080m12_04, 080m12_04_c, 080m12_06, 080m12_06_03, 080m12_07, 080m12_10',/continue
		return, -1
	end
	endcase
	transmission*=lyot_correction
	
	case pupil_mask_string of
	'CLEAR': apod_correction=(1.0/0.45) ; actually a tad oversized - but accounted for by Lyot/telescope
	'CLEARGP': apod_correction=(1.0/0.45) ; has a secondary - but any calculation of flux should already account for this
	'NRM': lyot_correction=(0.06198/lyot_trans) ; From anand document - LenoxSTScI_delivery_APOD_NRM10withTHRUPUT.xlsx
	'Y': apod_correction=(0.45/0.45)
	'J': apod_correction=(0.45/0.45)
	'H': apod_correction=(0.45/0.45)
	'K1':  apod_correction=(0.405/0.45)
	'K2':  apod_correction=(0.36/0.45)
;	else: return, error('FAILURE (calc_transmission): No throughput defined for the given Apodizer')
	else: begin 
		message,'No throughput defined for the given Apodizer stop '+pupil_mask_string,/continue
		return, -1
	end

	endcase
	transmission*=apod_correction
		
; now compensate for filter transmissions
; must first divide by the H-band transmission at 1.55um 
; load H filter
filt_prof_H0=mrdfits( gpi_get_directory('GPI_DRP_CONFIG')+'/filters/GPI-filter-H.fits',1,/silent)
filt_155_trans=interpol(filt_prof_H0.transmission,filt_prof_H0.wavelength,1.55)
transmission/=filt_155_trans

; now multiply by the filter transmission of the central wavelength for the given filter

if keyword_set(without_filter) eq 0 then begin
	; load filters for integration	
filt_prof0=mrdfits( gpi_get_directory('GPI_DRP_CONFIG')+'/filters/GPI-filter-'+filter+'.fits',1,/silent)
; get central wavelength for this filter
	filt_cen_wave=gpi_get_constant('cen_wave_'+filter) ; in um
; we divide by the filter transmission at this wavelength in the final determination
filt_cen_wave_trans=interpol(filt_prof0.transmission,filt_prof0.wavelength, filt_cen_wave)
transmission*=filt_cen_wave_trans
endif

; determine the resolution

; each slice is how big in wavelength space
	case filter of
	 ; from Jeff's ATP report - 4.14 REQ-FPR-0620: Spectral Resolution
	'Y': resolution=39.0
	'J': resolution=36.0
	'H': resolution=51.0
	'K1':resolution=78.0
	'K2': resolution=91.0
	else: return, error('FAILURE (calc_transmission): No spectral resolution defined for the given filter')
	endcase


return, transmission

end