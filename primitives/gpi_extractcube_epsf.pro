;+
; NAME: gpi_extractcube_epsf
; PIPELINE PRIMITIVE DESCRIPTION: Assemble Spectral Datacube using ePSF 
;
;		This routine transforms a 2D detector image in the dataset.currframe input
;		structure into a 3D data cube in the dataset.currframe output structure.
;   This routine extracts data cube from an image using an inversion method along the dispersion axis
;    
;
;
; KEYWORDS: 
; GEM/GPI KEYWORDS:
; OUTPUTS:
;
; PIPELINE COMMENT: Extract a 3D datacube from a 2D image. Spatial integration (3 pixels) along the dispersion axis
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="1" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="CalibrationFile" Type="String" CalFileType="mlenspsf" Default="AUTOMATIC" Desc="Filename of the mlens-PSF calibration file to be read"
; PIPELINE ARGUMENT: Name="ReuseOutput" Type="int" Range="[0,1]" Default="0" Desc="1: keep output for following primitives, 0: don't keep"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="0" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 2.0
; PIPELINE CATEGORY: SpectralScience, Calibration
;
; HISTORY:
; 	Originally by Jerome Maire 2007-11
;   2012-02-01 JM: adapted to vertical dispersion
;   2012-02-15 JM: adapted as a pipeline module
;   2013-08-07 ds: idl2 compiler compatible 
;   2013-12-16 MP: CalibrationFile argument syntax update. 
;   2014-07-18 JM: implemented ePSF instead of DST simulated PSF
;-
function gpi_extractcube_epsf, DataSet, Modules, Backbone


primitive_version= '$Id: gpi_extractcube_epsf.pro 2511 2014-02-11 05:57:27Z maire $' ; get version from subversion to store in header history
;calfiletype='mlenspsf' 
calfiletype='epsf' 

@__start_primitive

time0=systime(1,/seconds) ; this is for speed testing

; bad pixels excluded from the extraction later - but they first must be identified here - not in the loops

; DQ bit mask:
		;   0 = bad pixel, do not use if set
		;   1 = raw value was saturated
		;   2 = pixel diff between consecutive frames exceeds saturation
		;	3,4 = related to UTR calculations, do not indicated bad pixels
		; bits 0,1,2 = 7
		bpfromDQ = (*(dataset.currDQ) and 7) ne 0
		wbpfromDQ = where(bpfromDQ, bpfromDQcount)
		bad_pix_mask=bytarr(2048,2048)
		bad_pix_mask[wbpfromDQ] = 1
		
		; MP (temporary?) fix for missed cold pixels: also repair anything super negative
		negative_bad_thresh = -50 ; this is arbitrary!
		wlow = where(*dataset.currframe lt negative_bad_thresh, lowct) ; should be an adjustible thresh, or based on read noise * n * sigma?
		backbone->set_keyword, 'HISTORY', 'Found '+strc(lowct)+' additional very negative pixels (< -50 cts) in that image. ', ext_num=0
		backbone->Log,  'Found '+strc(lowct)+' additional very negative pixels (< -50 cts) in that image. ', depth=2
		bad_pix_mask[wlow] = 1 ; 1 means bad in a bad pixel mask


; load in the common block for ePSF
 common hr_psf_common, c_psf, c_x_vector_psf_min, c_y_vector_psf_min, c_sampling

my_filename_with_the_PSFs=c_File

;get the necessary epsfs calib files
High_res_PSFs = gpi_highres_microlens_psf_read_highres_psf_structure(my_filename_with_the_PSFs, [281,281,1])
 ;get the corresponding psf
  ptr_obj_psf = gpi_highres_microlens_psf_get_local_highres_psf(high_res_psfs,[141,141,0],/preserve_structure, valid=valid)
; put highres psf in common block for fitting
c_psf = (*ptr_obj_psf).values
; put min values in common block for fitting
c_x_vector_psf_min = min((*ptr_obj_psf).xcoords)
c_y_vector_psf_min = min((*ptr_obj_psf).ycoords)
; determine hte sampling and put in common block
c_sampling=round(1/( ((*ptr_obj_psf).xcoords)[1]-((*ptr_obj_psf).xcoords)[0] ))

; define size of the ePSF array;
;PI: why was this at 51? seems uncessarily large - JEROME looking at this
gridnbpt=51

tmp=findgen(gridnbpt)-gridnbpt/2
xgrid=rebin(tmp,gridnbpt,gridnbpt)
ygrid=rebin(transpose(tmp),gridnbpt,gridnbpt)

psf=gpi_highres_microlens_psf_evaluate_detector_psf(xgrid, ygrid, [.2,.2,1.])
;psfn=psf/total(psf)

  ;get the 2D detector image
  det=*(dataset.currframe[0])
  dim=(size(det))[1]
  detector_array=fltarr(dim,dim)
  nlens=(size(wavcal))[1]       ;pixel sidelength of final datacube (spatial dimensions) 
  dim=(size(det))[1]            ;detector sidelength in pixels

  ;error handle if readwavcal or not used before
  if (nlens eq 0) || (dim eq 0)  then $
     return, error('FAILURE ('+functionName+'): Failed to load data.') 


  ;define the common wavelength vector with the FILTER1 keyword:
   filter = gpi_simplify_keyword_value(backbone->get_keyword('IFSFILT', count=ct))
  
  ;error handle if FILTER1 keyword not found
  if (filter eq '') then $
     return, error('FAILURE ('+functionName+'): IFSFILT keyword not found.') 

  ;get length of spectrum
  sdpx = calc_sdpx(wavcal, filter, xmini, CommonWavVect)-2
  if (sdpx < 0) then return, error('FAILURE ('+functionName+'): Wavelength solution is bogus! All values are NaN.')
  
  ;get tilts of the spectra included in the wavelength solution:
  tilt=wavcal[*,*,4]

  cwv=get_cwv(filter)
  CommonWavVect=cwv.CommonWavVect
  lambdamin=CommonWavVect[0]
  lambdamax=CommonWavVect[1]
  lambda=cwv.lambda 

psfmlens = psf & mkhdr, HeaderCalib,psf
 
 szpsfmlens=(size(psf))[1]
  dimpsf=(size(psf))[1]          ;PI: isn't this just the gridnbpt variable above?
szpsf = size(psf)

        ;nlam defines how many spectral channels for the inversion 
      	nlam=13.
         
        psfmlens2=fltarr(szpsfmlens,szpsfmlens,nlam)
        lambda2=fltarr(nlam)
        
		; this uses the extremes - but this is configured using values so
		; we can use the 50 or 80% throughput points instead
		max_l=max(lambda)
		min_l=min(lambda)

; if you do NOT want samples on the end use this
        for qq=0,nlam-1 do lambda2[qq]=(max_l-min_l)/(nlam)*(qq+0.5)+min_l
; if you DO want samples on the end use this
 for qq=0,nlam-1 do lambda2[qq]=(max_l-min_l)/(nlam-1)*(qq)+min_l

;		window,2
;        plot,lambda,lambda,xr=[1.45,1.85],/xs
;        oplot,lambda2,lambda2,psym=2

 cubef3D=dblarr(nlens,nlens,nlam)+ !values.f_nan;create the datacube
      
 ;define coordinates for each spectral channel
 szwavcal=size(wavcal)
 xloctab=fltarr(szwavcal[1],szwavcal[2],nlam)
 yloctab=fltarr(szwavcal[1],szwavcal[2],nlam)
 for lam=0,nlam-1 do begin
      loctab=(change_wavcal_lambdaref( wavcal, lambda2[lam]))
      xloctab[*,*,lam]=loctab[*,*,1]
      yloctab[*,*,lam]=loctab[*,*,0]
 endfor
         
        ; define how many rows and columns of pixels to use in the raw image for the inversion of a single lenslet
        ; PI; I think this is an issue since the microlens PSFS are only 4 pixels wide...
		; PI: so this means that larg should be 1? can it be a non-integer?
		; PI: I tried 1 - but it didn't make a difference - so i left it at 2
		
		 larg=2 ; nb of columns parallel to the dispersion axis = (2*larg + 1)
         longu=20 ; nb of rows along the spectrum  ; PI: longu should be set by spdx no ?

bad_pix_count=0 
         ; do the inversion extraction for all lenslets
for xsi=0,nlens-1 do begin    
  print, "mlens PSF invert method for datacube extraction, row #",xsi," /",nlens-1   
     for ysi=0,nlens-1 do begin   


	 ; im lazy so only going ot use a small section
;for xsi=185,185+20 do begin    
;  print, "mlens PSF invert method for datacube extraction, row #",xsi," /",nlens-1   
;     for ysi=95,95+20 do begin   

;this is for just a single lenslet
; for xsi=185,186 do begin    
;  print, "mlens PSF invert method for datacube extraction, row #",xsi," /",nlens-1   
;     for ysi=95,96 do begin   



    ; get the locations on the image where intensities will be extracted:
     x3=xloctab[xsi,ysi,0]  ;xmini[xsi,ysi]
     y3= yloctab[xsi,ysi,0]  ;wavcal[xsi,ysi,1]+(wavcal[xsi,ysi,0]-x3)*tan(tilt[xsi,ysi])	


; This checks if there is a spectrum associated with the spaxel (takes care of oodles of NaN's in image) 
; this can definitely be sped up
if finite(x3) eq 0 then continue
if finite(y3) eq 0 then continue
if (x3 lt 0) or (x3 ge 2048) or (y3 le 1) or (y3 ge 2048) then continue
; original
;  if finite(x3) && finite(y3) && (x3 gt 0) && (x3 lt 2048) && (y3 gt 1) && (y3 lt 2048) then continue
 

 ;get the corresponding psf
  ptr_obj_psf = gpi_highres_microlens_psf_get_local_highres_psf(high_res_psfs,[xsi,ysi,0],/preserve_structure, valid=valid)
; put highres psf in common block for fitting
c_psf = (*ptr_obj_psf).values

	epsf_subsamp=5.0 ; epsf is sampled 5 times higher in each direction than the detector psf
			
; the psfs have residual crosstalk terms in the corners
; normal usage of chopping hte image into sections somewhat removes this
; but this isn't performed here, so i'll just set the other bits to zero
; this is a terribly dirty hack and must be fixed.

; PI: want to mask out the pixels that are too far from the peak
; this is horribly dirty and should actually be taken care of in the ePSF - not here
; my apologies 
	sz=size(c_psf)
	junk=max(c_psf,/nan,ind)
	xind=ind mod sz[1]
	yind=ind / sz[1]
; anything 3 pixels away from the peak or more is zeroed here
	c_psf[0:(xind-3*epsf_subsamp)>0,*]=0
	c_psf[(xind+3*epsf_subsamp)<(sz[1]-1):*,*]=0
	c_psf[*,0:(yind-3*epsf_subsamp)>0]=0
	c_psf[*,(yind+3*epsf_subsamp)<(sz[2]-1):*]=0

;PI: should normalize the high-res PSF, not the detector sampled one - explained below
c_psf/=(total(c_psf,/nan)/25.0)  ; epsf is 25 times the sampling of a detector sampled psf

; put min values in common block for fitting
c_x_vector_psf_min = min((*ptr_obj_psf).xcoords)
c_y_vector_psf_min = min((*ptr_obj_psf).ycoords)
; determine hte sampling and ploput in common block
;PI : I am not sure why this is rounded... it's rounded in my code as well.. but i have no idea why... 
c_sampling=round(1/( ((*ptr_obj_psf).xcoords)[1]-((*ptr_obj_psf).xcoords)[0] ))

 

 ;;; THIS ENTIRE SECTION NEEDS TO BE REDONE

      ;choice of pixels for the inversion
      xchoiceind=[0.]   ; these are actually coordinates not indicies of arrays
      ychoiceind=[0.]; these are actually coordinates not indicies of arrays

      for nl=0,nlam-1 do begin
        if (round(xloctab[xsi,ysi,nl])+larg lt 2048) && (round(yloctab[xsi,ysi,nl]) lt 2048) then begin
        ;avoid pairs when nlam>sdpx
            if (nl eq 0) || ~( (round(xloctab[xsi,ysi,nl-1]) eq round(xloctab[xsi,ysi,nl])) && (round(yloctab[xsi,ysi,nl-1]) eq round(yloctab[xsi,ysi,nl])))  then begin
              for clarg=-larg,larg do xchoiceind=[xchoiceind,round(xloctab[xsi,ysi,nl])+clarg>0]
              for clarg=-larg,larg do ychoiceind=[ychoiceind,round(yloctab[xsi,ysi,nl])>0]
            endif  
         endif     
                  
      endfor
; now remove the zero at the beginning of the array
      xchoiceind=xchoiceind[1:(n_elements(xchoiceind)-1)]
      ychoiceind=ychoiceind[1:(n_elements(ychoiceind)-1)]
      
      ;if nlam<sdpx, some pixels might be missing when doing the extraction, so add them
      holes=where((ychoiceind-shift(ychoiceind,1)) le -2,ch) ;are there holes ?
      if ch ge 1 then begin
        for chole=0,ch-1 do begin ;for each detected holes, fill it
            nbpixhole=ychoiceind[holes[chole]-1]-ychoiceind[holes[chole]]-1
            for eachpixhole = 0, nbpixhole-1 do begin
              for clarg=-larg,larg do xchoiceind=[xchoiceind,round(xchoiceind[holes[chole]+larg]+((eachpixhole+1.)/(nbpixhole))*(xchoiceind[holes[chole]-larg-1]-xchoiceind[holes[chole]+larg]))+clarg>0]
              for clarg=-larg,larg do ychoiceind=[ychoiceind,round(ychoiceind[holes[chole]-1] - eachpixhole - 1)>0]
            endfor  
        endfor
      endif
      

; now must remove the bad pixels from the array
; surely there is a move clever way to do this
; it does not appear to slow things down much (~1.5s our of 78)
 
if 1 eq 1 then begin
ind=-1
; the DQ mask 

for v=0,N_ELEMENTS(xchoiceind)-1 do if bad_pix_mask[xchoiceind[v],ychoiceind[v]] ne 0 or finite((*dataset.currframe[0])[xchoiceind[v],ychoiceind[v]]) eq 0  then ind=[ind,[v]]

if N_ELEMENTS(ind) gt 1 then begin
	;chop off the -1
	ind=ind[1:*]
	remove,ind,xchoiceind,ychoiceind
	bad_pix_count+=N_ELEMENTS(ind)
endif
	
endif
;;;; END SECTION THAT NEEDS REWRITE

; get the pixel positions of the chosen wavelengths
    dx2L=reform(xloctab[xsi,ysi,*] )
    dy2L=(reform(yloctab[xsi,ysi,*] ))  
				
; now loop over the number of chosen psfs per lenset
		for nl=0,nlam-1 do begin            
             ; get the detector sampled mlens psf for the given position
			psf=gpi_highres_microlens_psf_evaluate_detector_psf(xgrid, ygrid, [(dx2L[nl]-floor(dx2L[nl])) ,(dy2L[nl]-floor(dy2L[nl])) ,1.])
    	                                
            ;recenter the psf to correspond to its location onto the spectrum
            xshift=floor(dx2L[nl])-floor(dx2L[0])
            yshift=floor(dy2L[nl])-floor(dy2L[0])
            ; does this ever involve the wrapping of non-zero values to the otherside? 
            psfmlens2[0,0,nl]=SHIFT(psf,xshift,yshift)
                      
        endfor
        psfmlens4=reform(psfmlens2,szpsf[1]*szpsf[2],nlam)
                  
        spectrum=reform(psfmlens4#(fltarr(nlam)+1.),szpsf[1],szpsf[2])  ;;Calcul d'un spectrum 
          
		; PI: i don't understand this bit at all... Jerome will fix
        tmpx = floor(dx2L[0])
        tmpy = floor(dy2L[0])
          indxmin= (tmpx-(dimpsf-1)/2) > 0
                indxmax= (tmpx+(dimpsf-1)/2-1) < (dim-1)
                indymin= (tmpy-(dimpsf-1)/2) > 0
                indymax= (tmpy+(dimpsf-1)/2-1) < (dim-1)

    
                aa = -(tmpx-(dimpsf-1)/2)
                bb = -(tmpy-(dimpsf-1)/2)
  
                ; for residual purpose:
				; why is this piece only a 50x50 when everything else if 51x51 ? Jerome investigating
                detector_array[indxmin:indxmax,indymin:indymax]+=  spectrum[indxmin+aa: indxmax+aa, indymin+bb:indymax+bb]
                

                psfmat=fltarr(n_elements(xchoiceind),nlam)
         for nelam=0,nlam-1 do begin
                  
              for nbpix=0,n_elements(xchoiceind)-1 do $
                  psfmat[nbpix,nelam]=psfmlens2[xchoiceind[nbpix]+aa,ychoiceind[nbpix]+bb,nelam]
                  
         endfor

;PI: What does this do?
    if ((tmpx-larg) lt 0) OR  ((tmpx+larg) ge (dim-1)) OR (tmpy lt 0) OR ((tmpy+longu-1) ge (dim-1)) then  flagedge=0 else flagedge=1

		; create intensity array
        bbc=fltarr(n_elements(xchoiceind))
        for nel=0,n_elements(xchoiceind)-1 do bbc[nel]=det[xchoiceind[nel],ychoiceind[nel]]
                
		; this is just to look at the pixels being used in the extraction
		if 1 eq 1 then begin 
		  ; want to see the pixels being used for the intensity array
		  ; don't wnat the entire 2048x2048, so just make it smaller 
          stamp=fltarr(dimpsf,dimpsf)
		  for nel=0,n_elements(xchoiceind)-1 do stamp[xchoiceind[nel]-min(xchoiceind),ychoiceind[nel]-min(ychoiceind)]=det[xchoiceind[nel],ychoiceind[nel]]
; this is where you can check 
		endif
        
		
		 ;;invert the PSF array and multiply by the intensity array to get flux

; Dmitry suggests "Depending on the machine and the array size, the LAPACK wrapper (LA_SVD) might give you a free speed boost."
         SVDC, transpose(psfmat), W, U, V , /double
         ; Compute the solution and print the result: 
         if flagedge eq 1 then  flux= SVSOL(U, W, V, bbc, /double) else flux=fltarr(nlam)+!values.f_nan
          
		; PI: why is the 18 hard coded here?
         cubef3D[xsi,ysi,*]=flux*(float(nlam)/18.) ;this is normalized to take into account the number of slices we considered with respect to the length of spectra
         
        ; check the reconstruction?
		 if 1 eq 1 then begin 
		   reconspec=fltarr(dimpsf,dimpsf)
           for zl=0,nlam-1 do  reconspec+=flux[zl]*psfmlens2[*,*,zl]
          ; want to make it so we can subtract the determined spectrum from the actual spectrum to look at residuals
		  
		 endif
  endfor ; end loop over lenslet (ysi)
  endfor ; end loop over lenslet (xsi)

print,'bad_pix_count = '+strc(bad_pix_count)

print,'Time to run extraction = '+strc(systime(1,/seconds)-time0)+' seconds)

  suffix='-spdci'
  ; put the datacube in the dataset.currframe output structure:
   if tag_exist( Modules[thisModuleIndex],"ReuseOutput") && (float(Modules[thisModuleIndex].ReuseOutput) eq 1.)  then begin
    *(dataset.currframe[0])=cubef3D

      ;create keywords related to the common wavelength vector:
      backbone->set_keyword,'NAXIS',3, ext_num=1
      backbone->set_keyword,'NAXIS1',nlens, ext_num=1
      backbone->set_keyword,'NAXIS2',nlens, ext_num=1
      backbone->set_keyword,'NAXIS3',nlam, ext_num=1
      
      backbone->set_keyword,'CDELT3',(lambda2[1]-lambda2[0]),'wav. increment', ext_num=1
      ; FIXME this CRPIX3 should probably be **1** in the FORTRAN index convention
      backbone->set_keyword,'CRPIX3',0.,'pixel coordinate of reference point', ext_num=1
      backbone->set_keyword,'CRVAL3',lambda2[0],'wav. at reference point', ext_num=1
      backbone->set_keyword,'CTYPE3','WAVE', ext_num=1
      backbone->set_keyword,'CUNIT3','microms', ext_num=1
      backbone->set_keyword,'HISTORY', functionname+": Inversion datacube extraction applied.",ext_num=0

      @__end_primitive
    endif else begin  
        hdr=*(dataset.headersExt)[numfile]
        sxaddpar, hdr, 'NAXIS',3
        sxaddpar, hdr, 'NAXIS1',nlens
        sxaddpar, hdr, 'NAXIS2',nlens
        sxaddpar, hdr, 'NAXIS3',uint(nlam),after="NAXIS2"
        
        sxaddpar, hdr, 'CDELT3',(lambda2[1]-lambda2[0])
        sxaddpar, hdr, 'CRPIX3',0.
        sxaddpar, hdr, 'CRVAL3',lambda2[0]
        sxaddpar, hdr, 'CTYPE3','WAVE'
        sxaddpar, hdr, 'CUNIT3','microms'
        sxaddpar, hdr, 'HISTORY', functionname+": Inversion datacube extraction applied."
   
            if tag_exist( Modules[thisModuleIndex], "Save") && ( Modules[thisModuleIndex].Save eq 1 ) then begin
              if tag_exist( Modules[thisModuleIndex], "gpitv") then display=fix(Modules[thisModuleIndex].gpitv) else display=0 
              b_Stat = save_currdata( DataSet,  Modules[thisModuleIndex].OutputDir, suffix, savedata=cubef3D, saveheader=hdr, display=display)
              if ( b_Stat ne OK ) then  return, error ('FAILURE ('+functionName+'): Failed to save dataset.')
            endif else begin
              if tag_exist( Modules[thisModuleIndex], "gpitv") && ( fix(Modules[thisModuleIndex].gpitv) ne 0 ) then $
                  Backbone_comm->gpitv, double(cubef3D), ses=fix(Modules[thisModuleIndex].gpitv)
            endelse

  endelse

end

