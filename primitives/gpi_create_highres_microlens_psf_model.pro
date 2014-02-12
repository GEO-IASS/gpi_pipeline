;+
; NAME:  gpi_create_highres_microlens_psf_model
; PIPELINE PRIMITIVE DESCRIPTION: Create High-Resolution Microlens PSF Model
; 
; This primitive is based on the determination of a high resolution PSF for each lenslet. It uses an adapted none iterative algorithm from the paper of Jay Anderson and Ivan R. King 2000.
; 
; INPUTS:  Multiple 2D images with appropriate illumination
; OUTPUTS: High resolution microlens PSF empirical model
;
; PIPELINE COMMENT: Create a few calibrations files based on the determination of a high resolution PSF.
; PIPELINE ARGUMENT: Name="filter_wavelength" Type="string" Range="" Default="" Desc="Narrowband filter wavelength"
; PIPELINE ARGUMENT: Name="flat_field" Type="int" Range="[0,1]" Default="0" Desc="Is this a flat field"
; PIPELINE ARGUMENT: Name="flat_filename" Type="string" Default="" Desc="Name of flat field"
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="1" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="2" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 4.01
; PIPELINE CATEGORY: Calibration
;
; HISTORY:
;     Originally by Jean-Baptiste Ruffio 2013-06
;     2014-01-23 MP: Rename and documentation update
;-
function gpi_create_highres_microlens_psf_model, DataSet, Modules, Backbone
  primitive_version= '$Id$' ; get version from subversion to store in header history
@__start_primitive
  
  ;========  First section: Checking of inputs and initialization of variables depending on observing mode ==========
  ; Note: in the below, comments prefaced by "MP:" are added by Marshall during
  ; his attempt to read through and understand the details of JB's code...


  if tag_exist( Modules[thisModuleIndex], "filter_wavelength") then filter_wavelength=string(Modules[thisModuleIndex].filter_wavelength) else filter_wavelength=''
  if tag_exist( Modules[thisModuleIndex], "flat_field") then flat_field=float(Modules[thisModuleIndex].flat_field) else flat_field=0
  if tag_exist( Modules[thisModuleIndex], "flat_filename") then flat_filename=string(Modules[thisModuleIndex].flat_filename) else flat_filename=""
  
  if filter_wavelength eq '' and flat_field eq 0 then return, error(' No narrowband filter wavelength specified. Please specify a wavelength and re-add to queue')
  
  filter = gpi_simplify_keyword_value(backbone->get_keyword('IFSFILT', count=ct))
	disperser = gpi_simplify_keyword_value(backbone->get_keyword('DISPERSR', indexFrame=nfiles))
	nfiles=dataset.validframecount
 
  if nfiles eq 1 then begin
     image=*(dataset.currframe[0])
     
	 ; MP: I don't understand this part - why has JB hard coded a specific flat
	 ; field here? FIXME
	; PI: This was me doing testing - never had a chance to clean up before you started workingà
	; on it so i had to commit with stuff like this still in it (although not used)
     if keyword_set(flat_filename) eq 1 then begin
        stop
        flat_filename="/home/LAB/gpi/data/Reduced/130703/flat_field_arr_130702S0043.fits"
        flat=mrdfits(flat_filename)
        flat[where((flat) eq 0 or finite(flat) eq 0)]=1.0
        image/=flat
     endif
     sz=size(image) 
     if sz[1] ne 2048 or sz[2] ne 2048 then begin
        backbone->Log, "ERROR: Image is not 2048x2048, don't know how to handle it in microlens PSF measurements."
        return, NOT_OK
     endif
  endif
  
  ;declare variables based on which DISPERSR is selected
  ; MP: And then cut out the postage stamps around each PSF!
  backbone->Log, "Cutting out postage stamps around each lenslet PSF"
  case disperser of
     'PRISM': begin
        width_PSF = 4				; size of stamp? 
				n_per_lenslet = 1		; there is only 1 PSF per lenslet in spectral mode                
        sub_pix_res_x = 5		;sub_pixel resolution of the highres ePSF
        sub_pix_res_y = 5		;sub_pixel resolution of the highres ePSF
        cent_mode = "BARYCENTER"
				; if we are working with narrowband filter data, we want the centroid to be at the maximum
				if filter_wavelength ne -1 then cent_mode="MAX"
        ; Create raw data stamps
			    time0=systime(1,/seconds)
          spaxels = gpi_highres_microlens_psf_extract_microspectra_stamps(disperser, dataset.frames[0:(nfiles-1)], dataset.wavcals[0:(nfiles-1)], width_PSF, /STAMPS_MODE) 
  				time_cut=systime(1,/seconds)-time0
     end
     'WOLLASTON': begin
        width_PSF = 7				; size of stamp?
				n_per_lenslet =2		; there are 2 PSFs per lenslet in polarimetry mode.
        sub_pix_res_x = 4		; sub_pixel resolution of the highres ePSF
        sub_pix_res_y = 4   ; sub_pixel resolution of the highres ePSF
        cent_mode = "MAX"
        ; Create raw data stamps
				spaxels = gpi_highres_microlens_psf_extract_microspectra_stamps(disperser, image, polcal, width_PSF, /STAMPS_MODE)
     end
  endcase

  common psf_lookup_table, com_psf, com_x_grid_PSF, com_y_grid_PSF, com_triangles, com_boundary

  diff_image = fltarr(2048,2048)	; MP: difference image, output at end of calculation? PI: Yes
  model_image = fltarr(2048,2048)		; new modeled image - output at end of calculation
  
  n_neighbors = 4               ; number on each side - so 4 gives a 9x9 box - 3 gives a 7x7 box
  ; set up a lenslet jump to improve speed - normally the step would be 2*n_neighbors+1
  ; so this makes it (2*n_neighbors+1)*loop_jump
	loop_jump=1                  ; the multiple of lenslets to jump

  ;  n_neighbors_flex = 3          ; for the flexure shift determination - not currently used

; determine the cutout size- this is not always the same as width_PSF
; and the y-axis size is determined by the calibration file
  values_tmp = *(spaxels.values[(where(ptr_valid(spaxels.values)))[0]]) ; determine a box size
  nx_pix = (size(values_tmp))[1]	
  ny_pix = (size(values_tmp))[2]

  if (size(spaxels.values))[0] eq 4 then n_diff_elev = (size(spaxels.values))[4] else n_diff_elev = 1
  ; Create data structure for storing high-res PSF:
  PSF_template = {values: fltarr(nx_pix*sub_pix_res_x+1,ny_pix*sub_pix_res_y+1), $
                  xcoords: fltarr(nx_pix*sub_pix_res_x+1), $
                  ycoords: fltarr(ny_pix*sub_pix_res_y+1), $
                  tilt: 0.0,$		; MP: ???
                  id: [0,0,0] }		; MP: ???
  
                                ;replace the 281 by variables 
  PSFs = ptrarr(281, 281, n_per_lenslet)
  fitted_spaxels = replicate(spaxels,1)
  fit_error_flag = intarr(281, 281, n_per_lenslet)
  
  time0=systime(1) 
; start the iterations
; the following (it_flex_max) declares the number of iterations
; over the flexure loop - so the RHS of figure 8 in the Anderson paper
; this should probably be moved into a recipe keyword.

  it_flex_max = 2				; what is this? -MP  # of iterations for flexure? Not clear what is being iterated over.

; can't have multiple iterations if just one file - this should be a recipe failure

  if nfiles eq 1 then begin 
     it_flex_max=1
  endif
; make an array to look at the stddev as a function of iterations

  if flat_field eq 1 then flat_field_arr=fltarr(2048,2048,nfiles)

debug=1
  if debug eq 1 then begin
	; create a series of arrays to evaluate the fits for each iteration
                                ; want to watch how the weighted
                                ; STDDEV decreases with iterations etc
    stddev_arr=fltarr(281,281,n_per_lenslet,nfiles,it_flex_max)
    intensity_arr=fltarr(281,281,n_per_lenslet,nfiles,it_flex_max)
	 	weighted_intensity_arr=fltarr(281,281,n_per_lenslet,nfiles,it_flex_max)
    diff_intensity_arr=fltarr(281,281,n_per_lenslet,nfiles,it_flex_max)
    weighted_diff_intensity_arr=fltarr(281,281,n_per_lenslet,nfiles,it_flex_max)
  endif

; ########################
; start the flexure loop
; ########################
;

  imin_test = 0 & imax_test=280		; Iterate over entire field of view.
  jmin_test = 0 & jmax_test=280
; imin_test = 145 & imax_test = 155
; jmin_test = 145 & jmax_test = 155

; imin_test = 166-20 & imax_test = 177+20
; jmin_test = 166-20 & jmax_test = 177+20
  ; code check range
; imin_test = 148 & imax_test = 152
; jmin_test = 148 & jmax_test = 152

; the following is for pixel phase plotting only - it has no effect on any results
  pp_xind=166 & pp_yind=177
  pp_neighbors=8

  time1=systime(1,/seconds)
	; the following is the iteration over the flexure position fixes
	; so the right/outer loop in fig 8

  for it_flex=0,it_flex_max-1 do begin 
     backbone->Log, 'starting iteration '+strc(it_flex+1)+' of '+strc(it_flex_max)+' for flexure'
 
		time_it0=systime(1,/seconds)
        for k=0,n_per_lenslet-1 do begin ; MP: loop over # of spots per lenslet - only >1 for polarimetry

           ; now loop over each lenslet
           for i=imin_test,imax_test do begin				
              ;statusline, "Get and fit PSF: Fitting line "+strc(i+1)+" of 281 and spot "+strc(k+1)+" of "+strc(kmax+1)+" for iteration " +strc(it+1)+" of "+strc(it_max)
						
              for j=jmin_test,jmax_test do begin
								
                 ; see if there are any intensities and not all nans
				 ; MP: Skip if this is not a valid illuminated lenslet
                 if ~finite(spaxels.intensities[i,j,k]) or spaxels.intensities[i,j,k] eq 0.0 then continue
				
					time_ij0=systime(1,/seconds)

                     ; takes a chunk of the array to work with so you're not
                                ; passing the entire array
                    
                                ;TODO: it doesnt manage the edges
                    imin = max([0,(i-n_neighbors)])
                    imax = min([280,(i+n_neighbors)])
                    jmin = max([0,(j-n_neighbors)])
                    jmax = min([280,(j+n_neighbors)])
                    nspaxels = (imax-imin+1)*(jmax-jmin+1)*n_diff_elev
                                ;            stop
                                ; just reforms the array to be smaller
                    ptrs_current_stamps = reform(spaxels.values[imin:imax,jmin:jmax,k,*],nspaxels)
                    ptrs_current_xcoords = reform(spaxels.xcoords[imin:imax,jmin:jmax,k,*],nspaxels)
                    ptrs_current_ycoords = reform(spaxels.ycoords[imin:imax,jmin:jmax,k,*],nspaxels)
                    ptrs_current_masks = reform(spaxels.masks[imin:imax,jmin:jmax,k,*],nspaxels)
                   
										time_ij1 = systime(1,/seconds)

                    not_null_ptrs = where(ptr_valid(ptrs_current_stamps), n_not_null_ptrs)
                    current_stamps = fltarr(nx_pix,ny_pix,n_not_null_ptrs)
                    current_x0 = fltarr(n_not_null_ptrs)
                    current_y0 = fltarr(n_not_null_ptrs)
                    current_masks = fltarr(nx_pix,ny_pix,n_not_null_ptrs)

										time_ij2 = systime(1,/seconds)

                    for it_ptr = 0,n_not_null_ptrs-1 do begin
                       current_stamps[*,*,it_ptr] = *ptrs_current_stamps[not_null_ptrs[it_ptr]]
                       current_x0[it_ptr] = (*ptrs_current_xcoords[not_null_ptrs[it_ptr]])[0]
                       current_y0[it_ptr] = (*ptrs_current_ycoords[not_null_ptrs[it_ptr]])[0]
                       current_masks[*,*,it_ptr] = *ptrs_current_masks[not_null_ptrs[it_ptr]]
                    endfor
                    time_ij3 = systime(1,/seconds)

                    current_xcen = (spaxels.xcentroids[imin:imax,jmin:jmax,k,*])[not_null_ptrs]
                    current_ycen = (spaxels.ycentroids[imin:imax,jmin:jmax,k,*])[not_null_ptrs]
                    current_flux = (spaxels.intensities[imin:imax,jmin:jmax,k,*])[not_null_ptrs]
                    current_sky =  (spaxels.sky_values[imin:imax,jmin:jmax,k,*])[not_null_ptrs]
                    
                               
  	                time_ij4 = systime(1,/seconds)
										print, "Get and fit PSF: Fitting [line,column] ["+strc(i+1)+','+strc(j+1)+"] of 281 and spot "+strc(k+1)+" of "+strc(n_per_lenslet)
	
                    ptr_current_PSF = gpi_highres_microlens_psf_create_highres_psf($
																							 temporary(current_stamps), $
                                               temporary(current_xcen - current_x0), $
                                               temporary(current_ycen - current_y0), $
                                               temporary(current_flux), $
                                               temporary(current_sky), $
                                               nx_pix,ny_pix,$
                                               sub_pix_res_x,sub_pix_res_y, $
                                               MASK = temporary(current_masks),  $
                                ;XCOORDS = polspot_coords_x, $
                                ;YCOORDS = polspot_coords_y, $
                                               ERROR_FLAG = myerror_flag, $
                                               CENTROID_MODE = cent_mode, $
                                               HOW_WELL_SAMPLED = my_Sampling,$
                                               LENSLET_INDICES = [i,j,k], no_error_checking=1,$
											   /plot_samples )
					time_ij5 = systime(1,/seconds)

										; now fit the PSF to each elevation psf and each neighbour
					for f = 0,nfiles-1 do begin

						for pi=imin, imax do begin
							for pj=jmin, jmax do begin
							 
								time_f0 = systime(1,/seconds)
																
								; check to make sure pointer is valid
								if ptr_valid(spaxels.values[pi,pj,k,f]) eq 0 then continue
								first_guess_parameters = [spaxels.xcentroids[pi,pj,k,f], spaxels.ycentroids[pi,pj,k,f], spaxels.intensities[pi,pj,k,f]]
								ptr_fitted_PSF = gpi_highres_microlens_psf_fit_detector_psf($
														 *spaxels.values[pi,pj,k,f] - spaxels.sky_values[pi,pj,k,f], $
														 FIRST_GUESS = (first_guess_parameters),$
														 mask=*spaxels.masks[pi,pj,k,f],$
														 ptr_current_PSF,$
														 X0 = (*spaxels.xcoords[pi,pj,k,f])[0,0], $
														 Y0 = (*spaxels.ycoords[pi,pj,k,f])[0,0], $
														 FIT_PARAMETERS = best_parameters, $
														 /QUIET, $
													;                              /anti_stuck, $
														 ERROR_FLAG = my_other_error_flag, no_error_checking=1) ;
									
								time_f1 = systime(1,/seconds)
									
													; only store high-res psf in the place for which it was determined 
								if pi eq i and pj eq j then PSFs[i,j,k] = (ptr_current_PSF)
								fitted_spaxels.values[pi,pj,k,f] =temporary(ptr_fitted_PSF)
								fitted_spaxels.xcentroids[pi,pj,k,f] = best_parameters[0]
								fitted_spaxels.ycentroids[pi,pj,k,f] = best_parameters[1]
								fitted_spaxels.intensities[pi,pj,k,f] = best_parameters[2]
							endfor     ; end loop over pj
						endfor          ; end loop over pi
						time_f2 = systime(1,/seconds)
					
						;; #########################################                       
						;; FROM HERE TO THE ENDFOR IS JUST DEBUGGING
						;; #########################################
						
					
						value_to_consider = where(*spaxels.masks[i,j,k,f] eq 1)
						if value_to_consider[0] ne -1 then begin
                        diff_image[ (*spaxels.xcoords[i,j,k,f])[value_to_consider], (*spaxels.ycoords[i,j,k,f])[value_to_consider] ] = (*spaxels.values[i,j,k,f])[value_to_consider] - (spaxels.sky_values[i,j,k,f])[value_to_consider]-((*fitted_spaxels.values[i,j,k,f])*(*spaxels.masks[i,j,k,f]))[value_to_consider]
;                               ;  Create a modeled image - using the fitted PSFs
                         model_image[ (*spaxels.xcoords[i,j,k,f])[value_to_consider], (*spaxels.ycoords[i,j,k,f])[value_to_consider] ] += ((*fitted_spaxels.values[i,j,k,f])*(*spaxels.masks[i,j,k,f]))[value_to_consider]
                     
                              ; calculate the stddev
                          stddev_arr=fltarr(281,281,n_per_lenslet,nfiles,it_flex_max)

                           ; interested in the weighted stddev
                           ; weight by intensity
                        mask0=(*spaxels.masks[i,j,k,f])
												;make mask eq 0 values nan's
												ind= where(mask0 eq 0)
												if ind[0] ne -1 then mask0[where(mask0 eq 0)]=!values.f_nan
                        mask=(*spaxels.masks[i,j,k,f])[value_to_consider]
                        sz=size(mask0)

                        weights0=reform((*spaxels.values[i,j,k,f]) - (spaxels.sky_values[i,j,k,f]),sz[1],sz[2])*mask0
                        weights=((*spaxels.values[i,j,k,f])[value_to_consider] - (spaxels.sky_values[i,j,k,f])[value_to_consider])*mask
                        gain=float(backbone->get_keyword('sysgain'))
                        weights0=sqrt((*fitted_spaxels.values[i,j,k,f])*gain)/gain
                        weights=sqrt((*fitted_spaxels.values[i,j,k,f])[value_to_consider]*gain)/gain

                        intensity0=reform((*spaxels.values[i,j,k,f]) - (spaxels.sky_values[i,j,k,f]),sz[1],sz[2])*mask0
                        intensity=((*spaxels.values[i,j,k,f])[value_to_consider] - (spaxels.sky_values[i,j,k,f])[value_to_consider])*mask

                        diff0=mask0*(reform((*spaxels.values[i,j,k,f]) - (spaxels.sky_values[i,j,k,f]),sz[1],sz[2])-(*fitted_spaxels.values[i,j,k,f]))
                        diff=(*spaxels.values[i,j,k,f])[value_to_consider] - (spaxels.sky_values[i,j,k,f])[value_to_consider]-((*fitted_spaxels.values[i,j,k,f])*(*spaxels.masks[i,j,k,f]))[value_to_consider]
                        model=(*fitted_spaxels.values[i,j,k,f])*mask
                        w_mean=total(abs(diff)*weights,/nan)/total(weights,/nan)/total(mask,/nan)
                        weighted_intensity_arr[i,j,k,f,it_flex]=total(intensity*weights,/nan)/total(weights,/nan)
												intensity_arr[i,j,k,f,it_flex]=total(intensity,/nan)
                        stddev_arr[i,j,k,f,it_flex]= total(weights*(diff-w_mean)^2.0,/nan)/total(weights,/nan)
                        weighted_diff_intensity_arr[i,j,k,f,it_flex]=total(abs(weights*diff),/nan)/total(weights)
												diff_intensity_arr[i,j,k,f,it_flex]=total(abs(diff),/nan)

                        if i eq 125 and j eq 125 and f eq 0 then begin;and it_flex eq it_flex_max-1 then begin
                               ;loadct,0
                               ;window,1,retain=2,xsize=300,ysize=300,title='orig & fit- '+strc(i)+', '+strc(j)
                               sz=(*spaxels.values[150,150])
                               mask=(*spaxels.masks[i,j,k,f])
                               orig=mask*(*spaxels.values[i,j,k,f])
                               ;tvdl,orig,min(orig,/nan),max(orig,/nan)
                            
                               window,3,retain=3,xsize=300,ysize=300,title='orig & model- '+strc(i)+', '+strc(j)
                               fit=((*fitted_spaxels.values[i,j,k,f])*(*spaxels.masks[i,j,k,f]))
                               ;tvdl,[orig,fit],min(orig,/nan),max(orig,/nan)
                               window,2,retain=2,xsize=300,ysize=300,title='percentage residuals- '+strc(i)+', '+strc(j)
                               sky=mask*(spaxels.sky_values[i,j,k,f])
                               mask[where(mask eq 0)]=!values.f_nan
                               ;tvdl,mask*(orig-sky-fit)/fit,-0.1,0.1
                               
                               print, 'mean and weighted mean',  total(abs(mask*diff),/nan)/total(orig*mask,/nan), w_mean
                               
                               ;stop
                            endif ; display if
						endif     ; check for no dead values
						;; ####################            
						;; END OF DEBUG
						;; ####################
						;
						time_f3 = systime(1,/seconds)

					endfor      ; loop to fit psfs in elevation

					time_ij6 = systime(1,/seconds)
					;print, (time_ij1-time_ij0)/(time_ij6-time_ij0)
					;print, (time_ij2-time_ij1)/(time_ij6-time_ij0)
					;print, (time_ij3-time_ij2)/(time_ij6-time_ij0)
					;print, (time_ij4-time_ij3)/(time_ij6-time_ij0)

					;print, 'time to cut arrays', time_cut

					;print, '% of time to do get_psf', (time_ij5-time_ij4)/(time_ij6-time_ij0)
					;print, '% of time to do fit_psf', (time_ij6-time_ij5)/(time_ij6-time_ij0)
					;print, 'total time=',time_ij6-time_ij0

					; now we need to step in the number of neighbours
					j+=((2*n_neighbors)*loop_jump)

              endfor       ; end loop over j lenslets (columns?)
					i+=((2*n_neighbors)*loop_jump)
           endfor ; end loop over i lenslsets (rows?)
        endfor ; end loop over # of spots per lenslet  (1 for spectra, 2 for polarization)
        
        print, 'Iteration complete in '+strc((systime(1)-time0)/60.)+' minutes'
        ; put the fitted values into the originals before re-iterating
;		stop,'just about to modify centroids'
        spaxels.xcentroids = fitted_spaxels.xcentroids
        spaxels.ycentroids = fitted_spaxels.ycentroids
        spaxels.intensities= fitted_spaxels.intensities
   
; ####################################################
; NOW MOVING INTO THE TRANSFORMATION PART OF THE CODE 
; ####################################################
 
     ;set the first file as the reference image/elevation.
     ;All the transformations to go from one elevation to another are computed from that image or to that image.
     not_null_ptrs = where(finite(spaxels.xcentroids[imin_test:imax_test,jmin_test:jmax_test,*,0]), n_not_null_ptrs) ; select only the lenslets for which we have a calibration.
     ;The previous index vector will be used for all the images so it should be valid for all of them.
     ;This should be fine if the all the images were computed using the same wavelnegth solution which could be shifted using the lookup table.

;get the reference centroids coordinates (it's the only thing we need for this step)
     xcen_ref = (spaxels.xcentroids[imin_test:imax_test,jmin_test:jmax_test,*,0])[not_null_ptrs] 
     ycen_ref = (spaxels.ycentroids[imin_test:imax_test,jmin_test:jmax_test,*,0])[not_null_ptrs]
     
     degree_of_the_polynomial_fit = 2 ; degree of the polynomial surface used for the flexure correction
     ;declare the arrays which will contain the coefficients of the polynomial surface for every single image (ie elevation)
     ;The third dimension indicated which file to consider
     xtransf_ref_to_im = fltarr(degree_of_the_polynomial_fit+1,degree_of_the_polynomial_fit+1,nfiles) ;How to get the x coordinates of the centroids of the reference image into the current image (cf 3rd dimension index to select the image). 
     xtransf_im_to_ref = fltarr(degree_of_the_polynomial_fit+1,degree_of_the_polynomial_fit+1,nfiles) ;How to get the x coordinates of the centroids of the current image into the reference one. 
     ytransf_ref_to_im = fltarr(degree_of_the_polynomial_fit+1,degree_of_the_polynomial_fit+1,nfiles) ;How to get the y coordinates of the centroids of the reference image into the current image (cf 3rd dimension index to select the image). 
     ytransf_im_to_ref = fltarr(degree_of_the_polynomial_fit+1,degree_of_the_polynomial_fit+1,nfiles) ;How to get the y coordinates of the centroids of the current image into the reference one. 
     ;JB: Inverting the transformation analytically is dangerous because some of the coefficients are really close to zero so you may divide stuff by really small numbers.
     ; It tended to increase the noise. That's why we compute the two transformations im->ref and ref->im independentaly without using an inverse.
     
     ;loop over the other images with different elevations
     ; note that we only compute the
     ; f=0 position for pixel phase reasons

  ;We first compute the flexure transformation and then add the contribution of the current image to the mean position of the centroids.
     ;at the end of this loop we have all the transformation im->ref and ref>im for all the elevations and the mean position of the centroid in the reference image.
     ;The current transformation method uses 2d polynomial surface. Contrary to the linear interpolation (shift + tip/tilt), it takes into account the distortion in x depending on y (and y on x).

; mean position in referece arrays - for entire detector
; only really good for showing errors in flexure etc
     xcen_ref_arr=fltarr(N_ELEMENTS(xcen_ref),nfiles)
     ycen_ref_arr=fltarr(N_ELEMENTS(ycen_ref),nfiles)

        for f = 0,nfiles-1 do begin
 
     ; The transformation of the reference image into the reference one should be identity
   ;  xtransf_ref_to_im[1,0,0] = 1
   ;  xtransf_im_to_ref[1,0,0] = 1
   ;  ytransf_ref_to_im[0,1,0] = 1
   ;  ytransf_im_to_ref[0,1,0] = 1
  
    ;Get the centroids of the current image (ie elevation)
        xcen = (spaxels.xcentroids[imin_test:imax_test,jmin_test:jmax_test,*,f])[not_null_ptrs]
        ycen = (spaxels.ycentroids[imin_test:imax_test,jmin_test:jmax_test,*,f])[not_null_ptrs]
        
        ;Computes the transformation from the reference to the current image for the x coordinates
        ;Prepare the input for the sfit fitting function. xcen is function of xcen_ref and ycen_ref.
        data_sfit = [transpose(xcen_ref), transpose(ycen_ref),transpose(xcen)] 
        ;Fitting function with a polynamial surface of degree "degree_of_the_polynomial_fit".
        xcen_sfit = SFIT( data_sfit, degree_of_the_polynomial_fit, /IRREGULAR, KX=coef_sfit)
        ;Store the resulting coefficients 
        xtransf_ref_to_im[*,*,f] = coef_sfit 
        ;declare the new list of the reference xcentroids in the image
        ; from the current image (at a given elevation)
        xcen_ref_in_im = fltarr(n_elements(xcen_ref)) 
        ;Loop to compute xcen_ref_in_im using the previous coefficients. 
        for i=0,degree_of_the_polynomial_fit do for j= 0,degree_of_the_polynomial_fit do xcen_ref_in_im += xtransf_ref_to_im[i,j,f]*xcen_ref^j * ycen_ref^i
        
        ;Now, x coordinates, from the image to the reference. 
        data_sfit = [transpose(xcen), transpose(ycen),transpose(xcen_ref)]
        xcen_ref_sfit = SFIT( data_sfit, degree_of_the_polynomial_fit, /IRREGULAR, KX=coef_sfit )
        xtransf_im_to_ref[*,*,f] = coef_sfit
        xcen_in_ref = fltarr(n_elements(xcen_ref))
        for i=0,degree_of_the_polynomial_fit do for j= 0,degree_of_the_polynomial_fit do xcen_in_ref += xtransf_im_to_ref[i,j,f]*xcen^j * ycen^i
        
        ;Now, y coordinates, ref to im. 
        data_sfit = [transpose(xcen_ref), transpose(ycen_ref),transpose(ycen)]
        ycen_sfit = SFIT( data_sfit, degree_of_the_polynomial_fit, /IRREGULAR, KX=coef_sfit )
        ytransf_ref_to_im[*,*,f] = coef_sfit
        ycen_ref_in_im = fltarr(n_elements(xcen_ref))
        for i=0,degree_of_the_polynomial_fit do for j= 0,degree_of_the_polynomial_fit do ycen_ref_in_im += ytransf_ref_to_im[i,j,f]*xcen_ref^j * ycen_ref^i
        
        ;Now, y coordinates, im to ref. 
        data_sfit = [transpose(xcen), transpose(ycen),transpose(ycen_ref)]
        ycen_ref_sfit = SFIT( data_sfit, degree_of_the_polynomial_fit, /IRREGULAR, KX=coef_sfit )
        ytransf_im_to_ref[*,*,f] = coef_sfit
        ycen_in_ref = fltarr(n_elements(xcen_ref))
        for i=0,degree_of_the_polynomial_fit do for j= 0,degree_of_the_polynomial_fit do ycen_in_ref += ytransf_im_to_ref[i,j,f]*xcen^j * ycen^i

; we want the mean position in the reference
; already have the first component of the mean computed
; now add the component to the mean
        xcen_ref_arr[*,f] = xcen_in_ref
        ycen_ref_arr[*,f] = ycen_in_ref

; plot pixel phase if desired
; a stupid idl problem that naturally collapses arrays makes this only usable when f gt 1 at the moment
 				if 1 eq 1 and nfiles gt 1 then begin
					; pp_logs is just a dump variable at the moment, but can be used to track pp over iterations
					pp_logs=gpi_highres_microlens_plot_pixel_phase(spaxels.xcentroids[pp_xind-pp_neighbors:pp_xind+pp_neighbors,pp_yind-pp_neighbors:pp_yind+pp_neighbors,*,*],(spaxels.ycentroids[pp_xind-pp_neighbors:pp_xind+pp_neighbors,pp_yind-pp_neighbors:pp_yind+pp_neighbors,*,*]),pp_neighbors,n_per_lenslet,degree_of_the_polynomial_fit,xtransf_im_to_ref,ytransf_im_to_ref)
				endif

    endfor   ; ends loop over different elevations

;stop,"about to apply flexure correction to centroids"

; calculate the mean position of each mlens psf - but use a rejection
mean_xcen_ref=fltarr(N_ELEMENTS(xcen_ref))
mean_ycen_ref=fltarr(N_ELEMENTS(ycen_ref))

for i=0, N_ELEMENTS(xcen_ref)-1 do begin
	meanclip,xcen_ref_arr[i,*], tmp_mean, tmp,clipsig=2.5
	mean_xcen_ref[i]=tmp_mean
endfor

for i=0, N_ELEMENTS(ycen_ref)-1 do begin
	meanclip,ycen_ref_arr[i,*], tmp_mean,tmp, clipsig=2.5
	mean_ycen_ref[i]=tmp_mean
endfor

; transforms the mean positions of each spot back into their images
; replaces each centroid with this mean position
    ;THE RESULT OF THE NEXT LOOP HAS NOT BEEN CHECK YET.
     x_id = not_null_ptrs mod 281
     y_id = not_null_ptrs / 281
     z_id = not_null_ptrs / (281L*281L)

; determine indices of arrays to replace
		 ind_arr = array_indices(spaxels.xcentroids[imin_test:imax_test,jmin_test:jmax_test,*,0],not_null_ptrs)

;xcen_ref = (spaxels.xcentroids[imin_test:imax_test,jmin_test:jmax_test,*,0])[not_null_ptrs] 

     if nfiles ne 1 then begin
     	for f = 0,nfiles-1 do begin ; loop over each flexure position
				tmpx=(spaxels.xcentroids[imin_test:imax_test,jmin_test:jmax_test,*,f])[not_null_ptrs] 
				tmpy=(spaxels.ycentroids[imin_test:imax_test,jmin_test:jmax_test,*,f])[not_null_ptrs] 

        mean_xcen_ref_in_im = fltarr(n_elements(xcen_ref))
        for i=0,degree_of_the_polynomial_fit do for j= 0,degree_of_the_polynomial_fit do mean_xcen_ref_in_im += xtransf_ref_to_im[i,j,f]*mean_xcen_ref^j * mean_ycen_ref^i

        mean_ycen_ref_in_im = fltarr(n_elements(ycen_ref))
        for i=0,degree_of_the_polynomial_fit do for j= 0,degree_of_the_polynomial_fit do mean_ycen_ref_in_im += ytransf_ref_to_im[i,j,f]*mean_xcen_ref^j * mean_ycen_ref^i

       	if (size(ind_arr))[0] gt 2 then begin
					for zx=0L,N_ELEMENTS(ind_arr[0,*])-1 do begin
						spaxels.xcentroids[ind_arr[0,zx]+imin_test,ind_arr[1,zx]+jmin_test,ind_arr[2,zx],f] = mean_xcen_ref_in_im[zx]
	      		spaxels.ycentroids[ind_arr[0]+imin_test,ind_arr[1]+jmin_test,ind_arr[2],f] = mean_ycen_ref_in_im[zx]
					endfor
	 				endif else begin
						for zx=0L,N_ELEMENTS(ind_arr[0,*])-1 do begin
							spaxels.xcentroids[ind_arr[0,zx]+imin_test,ind_arr[1,zx]+jmin_test,*,f] = mean_xcen_ref_in_im[zx]
	      			spaxels.ycentroids[ind_arr[0,zx]+imin_test,ind_arr[1,zx]+jmin_test,*,f] = mean_ycen_ref_in_im[zx]
						endfor
					endelse
;stop,'in application of flexure correction'
;				spaxels.xcentroids[x_id,y_id,z_id,lonarr(n_elements(x_id))+f] = mean_xcen_ref_in_im
;        spaxels.ycentroids[x_id,y_id,z_id,lonarr(n_elements(x_id))+f] = mean_ycen_ref_in_im

        
     endfor                     ; ends loop over f to apply flexure correction (line 670)
  endif ; if statement to see if there is more than 1 file - 

     ;//////STOP HERE if you want to play with the pixel phase plots or the centroid coordinates in the different images.
     ;stop,'just before end of flexure correction' ; this is where JB_TEST.sav is created
     
  endfor ; end of flexure correction loop (over it_flex)

  
     print, 'Run complete in '+strc((systime(1)-time0)/60.)+' minutes'
    stop 
     writefits, "diff_image.fits",diff_intensity_arr
     writefits, "intensity_arr.fits",intensity_arr
     writefits, "stddev_arr.fits",stddev_arr

; #######################
; BUILD THE FLAT FIELD
; ######################
     if flat_field eq 1 then begin
                                ; because we cannot extract arrays
                                ; from arrays of pointers, we have to
                                ; extract them using loops
; probably best to create 1 flat per elevation - which was done in the
;                                                flat_field_arr
; but might have overlap as some pixels will have been used twice
        flat_field_arr2=fltarr(2048,2048,nfiles)
        lowfreq_flat1=fltarr(281,281,nfiles)
        lowfreq_flat2=fltarr(281,281,nfiles)
        for f=0, nfiles-1 do begin
           for k=0,n_per_lenslet-1 do for i=0,281-1 do for j=0,281-1 do begin
                                ; find values are are not masked.
              if ptr_valid(spaxels.masks[i,j,k,f]) eq 0 then continue
              value_to_consider = where(*spaxels.masks[i,j,k,f] eq 1)
              if value_to_consider[0] ne -1 then begin
                 flat_field_arr2[ (*spaxels.xcoords[i,j,k,f])[value_to_consider], (*spaxels.ycoords[i,j,k, f])[value_to_consider], replicate(f,N_ELEMENTS(value_to_consider)) ] = ((*spaxels.values[i,j,k,f])[value_to_consider] - (spaxels.sky_values[i,j,k,f]) )/((*fitted_spaxels.values[i,j,k,f]))[value_to_consider]
                 lowfreq_flat1[i,j,k,f]=total((*fitted_spaxels.values[i,j,k,f])[value_to_consider])
                 lowfreq_flat2[i,j,k,f]=total((*spaxels.values[i,j,k,f])[value_to_consider])
              endif      
           endfor
        endfor
; set the values with no flat info to NaN
ind=where(flat_field_arr2 eq 0.000)
if ind[0] ne -1 then flat_field_arr[ind]=!values.f_nan
; so now loop over each pixel and calculate the weighted mean
        final_flat=fltarr(2048,2048)
        weights=fltarr(2048,2048,nfiles)
        for n=0,nfiles-1 do weights[*,*,n]=(*(dataset.frames[n]))
        
        if nfiles eq 1 then $
           final_flat2=flat_field_arr2 $
           else final_flat2=total(weights*flat_field_arr2,3)/total(weights,3) 
           writefits, "flat_field_arr.fits",flat_field_arr

; for lenslet 135,135 
;tvdl, subarr(final_flat2,100,[953,978]),0,2
loadct,0
window,23,retain=2
;tvdl, subarr(final_flat2,100,[1442,1244]),0.9,1.1
;  for lenslet 166,177 
window,24,retain=2
image=*(dataset.currframe[0])
;tvdl, subarr(image,100,[1442,1244]),/log

endif ; end flat field creation

        
; ####################
; create flexure plots
; ####################

if f gt 1 then begin
; stored in xtransf_im_to_ref
xx=(fltarr(2048)+1)##findgen(2048)
xx1d=reform(xx,2048*2048)
yy=findgen(2048)##(fltarr(2048)+1)
yy1d=reform(yy,2048*2048)

xflex_trans_arr1d=fltarr(2048*2048,nfiles)
for f=0,nfiles-1 do $
	for i=0,degree_of_the_polynomial_fit do $
		for j= 0,degree_of_the_polynomial_fit do $
			xflex_trans_arr1d[*,f] += xtransf_im_to_ref[i,j,f]*xx1d^j * yy1d^i
; now put back into 2-d arrays
xflex_trans_arr2d=(reform(xflex_trans_arr1d,2048,2048,nfiles))
; we want the difference, so we must subtract the xx array
for f=0,nfiles-1 do xflex_trans_arr2d[*,*,f]-=xx

; now do it in the y-direction
yflex_trans_arr1d=fltarr(2048*2048,nfiles)
for f=0,nfiles-1 do $
	for i=0,degree_of_the_polynomial_fit do $
		for j= 0,degree_of_the_polynomial_fit do $
			yflex_trans_arr1d[*,f] += ytransf_im_to_ref[i,j,f]*xx1d^j * yy1d^i
; now put back into 2-d arrays
yflex_trans_arr2d=(reform(yflex_trans_arr1d,2048,2048,nfiles))
; we want the difference, so we must subtract the xx array
for f=0,nfiles-1 do yflex_trans_arr2d[*,*,f]-=yy

; evalute performance increase
window,2,retain=2,title='weighted % residual'
tmp=(weighted_diff_intensity_arr/weighted_intensity_arr)
plothist,tmp[*,*,*,*,0],xhist,yhist,/nan,bin=0.01,xr=[0,0.15],xs=1,charsize=1.5
plothist,tmp[*,*,*,*,0],/nan,bin=0.01,xr=[0,0.15],xs=1,charsize=1.5,yr=[0,max(yhist)*1.5],ys=1
if nfiles ne 1 then plothist,tmp[*,*,*,*,1],/nan,bin=0.01,xr=[0,0.15],xs=1,charsize=1.5,/noerase,linestyle=2,yr=[0,max(yhist)*1.5],ys=1,color=155

window,1,retain=2,title='non-weighted % residual'
tmp2=(diff_intensity_arr/intensity_arr)

plothist,tmp2[*,*,*,*,0],xhist,yhist,/nan,bin=0.01,xr=[0,0.15],xs=1,charsize=1.5
plothist,tmp2[*,*,*,*,0],/nan,bin=0.01,xr=[0,0.15],xs=1,charsize=1.5,yr=[0,max(yhist)*1.5],ys=1
if nfiles ne 1 then plothist,tmp2[*,*,*,*,1],/nan,bin=0.01,xr=[0,0.15],xs=1,charsize=1.5,/noerase,linestyle=2,yr=[0,max(yhist)*1.5],ys=1,color=155

endif

stop

  valid_psfs = where(ptr_valid(PSFs), n_valid_psfs)
  
  to_save_psfs = replicate(*PSFs[valid_psfs[0]],n_valid_psfs)
  
  for i=0,n_valid_psfs-1 do begin
     to_save_psfs[i] = *PSFs[valid_psfs[i]]
  endfor
  
  backbone->set_keyword, "ISCALIB", 'YES', 'This is a reduced calibration file of some type.'
  gpicaldb = Backbone_comm->Getgpicaldb()
  s_OutputDir = gpicaldb->get_calibdir()
                                ; ensure we have a directory separator, if it's not there already
  if strmid(s_OutputDir, strlen(s_OutputDir)-1,1) ne path_sep() then s_OutputDir+= path_sep()
  filenm = dataset.filenames[numfile]
                                ; Generate output filename
                                ; remove extension if need be
  base_filename = file_basename(filenm)
  extloc = strpos(base_filename,'.', /reverse_search)
  
  nrw_filt=strmid(strcompress(string(filter_wavelength),/rem),0,5)
  my_file_name=gpi_get_directory('GPI_REDUCED_DATA_DIR')+'highres-'+nrw_filt+'-psf_structure.fits'
  mwrfits,to_save_psfs, my_file_name,*(dataset.headersExt[numfile]), /create
  
;  psfs_from_file = read_psfs(my_file_name, [281,281,1])
 
  
  my_file_name = gpi_get_directory('GPI_REDUCED_DATA_DIR')+'highres-'+nrw_filt+'-psf-spaxels.fits'
  save, spaxels, filename=my_file_name
  
  my_file_name = gpi_get_directory('GPI_REDUCED_DATA_DIR')+'highres-'+nrw_filt+'-fitted_spaxels.fits'
  save, fitted_spaxels, filename=my_file_name

 ; cant save these files as fits since they're not pointers 
;  mwrfits,spaxels, my_file_name,*(dataset.headersExt[numfile])
;  
;  mwrfits,fitted_spaxels, my_file_name,*(dataset.headersExt[numfile])
;  stop
  ;how to read the fits with the psfs
;  rawarray =mrdfits(my_file_name,1)
;  PSFs = reform(rawarray, 281,281,2or1)
;  one_psf = PSFs[171,171,0].values
;  tvdl, one_psf
  
                                ;---- store the output into the backbone datastruct
  suffix = '-'+filter+'-'+nrw_filt+'PSFs'
  *(dataset.currframe)=diff_image
  dataset.validframecount=1
  backbone->set_keyword, "FILETYPE", "PSF residuals", /savecomment
  backbone->set_keyword, "ISCALIB", 'NO', 'This is NOT a reduced calibration file of some type.'
  
@__end_primitive
end

