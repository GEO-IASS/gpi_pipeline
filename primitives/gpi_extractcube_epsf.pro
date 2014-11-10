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

;Profiler, /CLEAR, /SYSTEM 
;Profiler, /CLEAR, /RESET
;profiler
;PROFILER, /SYSTEM
primitive_version= '$Id$' ; get version from subversion to store in header history
calfiletype='epsf' 

@__start_primitive

time0=systime(1,/seconds) ; this is for speed testing

; for noise estimation
gain=3.04 ; electrons /ADU
readnoise=22/3.04 ; 22 electrons /3.04 electrons per ADU

; load in the common block for ePSF
common hr_psf_common, c_psf, c_x_vector_psf_min, c_y_vector_psf_min, c_sampling


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
if bpfromDQcount gt 0 then $
bad_pix_mask[wbpfromDQ] = 1
		
; MP (temporary?) fix for missed cold pixels: also repair anything super negative
negative_bad_thresh = -50 ; this is arbitrary!
wlow = where(*dataset.currframe lt negative_bad_thresh, lowct) ; should be an adjustible thresh, or based on read noise * n * sigma?
backbone->set_keyword, 'HISTORY', 'Found '+strc(lowct)+' additional very negative pixels (< -50 cts) in that image. ', ext_num=0
backbone->Log,  'Found '+strc(lowct)+' additional very negative pixels (< -50 cts) in that image. ', depth=2
bad_pix_mask[wlow] = 1 ; 1 means bad in a bad pixel mask

bpmapsize=size(badpixmap)
if bpmapsize[1] eq 0 then begin
print, "Using the DQ/negative thresh  to find bad pixels...You should consider using the bad pixel map to make it better."
bad_pix_mask=bad_pix_mask;(*dataset.currdq[0])
endif else begin
bad_pix_mask=bad_pix_mask OR badpixmap ;(*dataset.currdq[0]) OR badpixmap
endelse
my_filename_with_the_PSFs=c_File

my_filename_with_the_psfs='/Users/patrickingraham/GPI/data/Reduced/backup_lenslet_psfs/140822i_highres-1650um-psf_structure.fits'
my_filename_with_the_psfs='/Users/patrickingraham/GPI/data/Reduced/backup_lenslet_psfs/140822h_highres-1650um-psf_structure.fits'
my_filename_with_the_psfs='/Users/patrickingraham/GPI/data/Reduced/backup_lenslet_psfs/140825a_highres-1650um-psf_structure.fits'
my_filename_with_the_psfs='/Users/patrickingraham/GPI/data/Reduced/backup_lenslet_psfs/140905b_highres-1650um-psf_structure.fits'

;140905b_highres-1650um-psf_structure.fits ; is the standars


;my_filename_with_the_psfs='/Users/patrickingraham/GPI/data/Reduced/backup_lenslet_psfs/140524_highres-2058um-psf_structure-updatedheaders.fits'


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
gridnbpt=7 ;keep it odd; defining size of epsf to be calculated - should be equal to or larger than 2*larg+1 ?

;
dimpsfx=49 ;keep it odd; defining the size of spectrum the following code will play with
dimpsfy=dimpsfx ; so testing showed that rectangular arrays SLOW it down !!!


tmp=findgen(gridnbpt)-gridnbpt/2
xgrid=rebin(tmp,gridnbpt,gridnbpt)
ygrid=rebin(transpose(tmp),gridnbpt,gridnbpt)

;psf=gpi_highres_microlens_psf_evaluate_detector_psf(xgrid, ygrid, [.2,.2,1.])
;psfn=psf/total(psf)

;get the 2D detector image
det=*(dataset.currframe[0])
dim=(size(det))[1]
detector_array=fltarr(dim,dim)
nlens=(size(wavcal))[1]       ;pixel sidelength of final datacube (spatial dimensions) 
dim=(size(det))[1]            ;detector sidelength in pixels

;print,'OFFSET OF SKY'
;Sky_offset=30 ; sky per pixel
sky_offset=0
det-=sky_offset

;error handle if readwavcal or not used before
if (nlens eq 0) || (dim eq 0)  then $
	return, error('FAILURE ('+functionName+'): Failed to load data.') 

; define the common wavelength vector with the FILTER1 keyword:
filter = gpi_simplify_keyword_value(backbone->get_keyword('IFSFILT', count=ct))
  
; error handle if FILTER1 keyword not found
if (filter eq '') then $
	return, error('FAILURE ('+functionName+'): IFSFILT keyword not found.') 

; get length of spectrum
sdpx = calc_sdpx(wavcal, filter, xmini, CommonWavVect)
if (sdpx < 0) then return, error('FAILURE ('+functionName+'): Wavelength solution is bogus! All values are NaN.')
  
; get tilts of the spectra included in the wavelength solution:
tilt=wavcal[*,*,4]

cwv=get_cwv(filter)
CommonWavVect=cwv.CommonWavVect
lambda=cwv.lambda 
lambda0=lambda

;psfmlens = psf & mkhdr, HeaderCalib,psf
 
; szpsfmlens=(size(psf))[1]
;  dimpsf=(size(psf))[1]          ;PI: isn't this just the gridnbpt variable above?
;szpsf = size(psf)

; #################################################################
; create placements in x,y,lambda where the ePSFs should be placed
; #################################################################

;nlam defines how many spectral channels for the inversion 
nlam=20.  ; this is one psf per pixel
nlam=18. 
;nlam=sdpx*3
;nlam=37
psfmlens2=fltarr(dimpsfx,dimpsfy,nlam)
lambda2=fltarr(nlam)
        
; this uses the extremes of the filter - but this is configured using values so
; we can use the 50 or 80% throughput points instead
max_l=max(lambda)
min_l=min(lambda)

; if you do NOT want samples on the maxima of the microspectra then use this
;for qq=0,nlam-1 do lambda2[qq]=(max_l-min_l)/(nlam)*(qq+0.5)+min_l
; if you DO want samples on the maxima of the microspectra then use this
for qq=0,nlam-1 do lambda2[qq]=(max_l-min_l)/(nlam-1)*(qq)+min_l

; interpolate wavelenght axis doesn't take this input well
; so just going to use lambda2=lambda for a moment

;lambda2=lambda


;		window,2
;        plot,lambda,lambda,xr=[1.45,1.85],/xs
;        oplot,lambda2,lambda2,psym=2

 cubef3D=dblarr(nlens,nlens,nlam)+ !values.f_nan;create the datacube
 cubef3Dbpix=intarr(nlens,nlens,nlam)+ !values.f_nan;create the datacube
      
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
larg=1 
;longu=20 ; nb of rows along the spectrum  ; PI: longu should be set by sdpx no ?
;longu=sdpx
bad_pix_count=0 ; this is just for debugging

;; do the inversion extraction for all lenslets
;for xsi=0,nlens-1 do begin    
;  print, "mlens PSF invert method for datacube extraction, row #",xsi," /",nlens-1   
;     for ysi=0,nlens-1 do begin   
;         epsf_debug=1


;this is for just a single lenslet
; 103,204 has a big bad section
; 103,37 is very diagonal
; 183,186 is used as a reference in create highres psf
;110, 102 - sat spot for 131210 - H - HD8049
;sx=165 & sy=198
sx=132 & sy=143  ; straight up and down spectrum

;sx=191 & sy=132

dsx=20 & dsy=20
 for xsi=sx-dsx,sx+dsx do begin    
 print, "mlens PSF invert method for datacube extraction, row #",xsi," /",nlens-1   
     for ysi=sy-dsy,sy+dsy do begin   
     epsf_debug=1


; This checks if there is a spectrum associated with the spaxel (takes care of oodles of NaN's in image) 
; this can definitely be sped up
if finite(xloctab[xsi,ysi,0]) eq 0 then continue
if finite(yloctab[xsi,ysi,0]) eq 0 then continue
;verify the xvalues are within range
if (xloctab[xsi,ysi,0] lt 0) or (xloctab[xsi,ysi,0] ge 2048) then continue
;verify the yvalues are within range
if (yloctab[xsi,ysi,0] le 1) or (yloctab[xsi,ysi,0] ge 2048) then continue
; original
;  if finite(x3) && finite(y3) && (x3 gt 0) && (x3 lt 2048) && (y3 gt 1) && (y3 lt 2048) then continue
 

 ;get the corresponding epsf
  ptr_obj_psf = gpi_highres_microlens_psf_get_local_highres_psf(high_res_psfs,[xsi,ysi,0],/preserve_structure, valid=valid)
; put highres psf in common block for fitting
c_psf = (*ptr_obj_psf).values

;subtract off the background of the ePSF - seems to make no difference
ind = where(c_psf ne 0 and finite(c_psf) eq 1,ct)
if ct gt 0 then sky= median(c_psf[ind]) else sky=0
		c_psf-=(sky)
	

; ####### TESTING
if 0 eq 1 then begin 
	; DECONVOLVE
	; ######################

 d_disp=0.015 ; um/detector pixel 
det_disp=0.015 ; um/detector pixel  
epsf_disp=0.015/5 ;um/epsf_pixel
sigma=(0.012/epsf_disp)/2.354  ;/ 1.5
psf1d=gauss_draw(findgen(120),[0.4,61,sigma])
psf2d=rebin(transpose(psf1d),60,120)

psf1d=gauss_draw(findgen(5),[0.4,2,sigma])
psf2d=rebin(transpose(psf1d),5,5)

psf2d/=total(psf2d)


image_deconv=[]
multipliers=[]
psf_ft=[]

c_psf0=c_psf
Niter=10
for i=1,Niter do max_entropy, c_psf, psf2d, image_deconv, multipliers,/no_ft; FT_PSF=psf_ft

if 0 eq 1 and xsi eq sx and ysi eq sy then begin
window,0
loadct,0
tvdl, c_psf/max(c_psf,/nan),0,1,position=0
 tvdl, image_deconv/max(image_deconv,/nan),0,1,position=1
tvdl, c_psf/max(c_psf,/nan)-image_deconv/max(image_deconv,/nan),position=2

window,1
tmp=max(c_psf,ind)
aa=array_indices(c_psf,ind)

plot, c_psf[16,61-10:61+10]/max(c_psf,/nan)
oplot, c_psf[16-10:16+10,61]/max(c_psf,/nan),color=cgcolor('blue')

oplot,image_deconv[16,61-10:61+10]/max(image_deconv,/nan),color=cgcolor('red')
stop
endif

;c_psf=image_deconv/total(image_deconv)*total(c_psf0)
;stop		

endif ; end the deconvolution
; ######## end testing

	
; the psfs have residual crosstalk terms in the corners
; normal usage of chopping hte image into sections somewhat removes this
; but this isn't performed here, so i'll just set the other bits to zero
; this is a terribly dirty hack and must be fixed.

; PI: want to mask out the pixels that are too far from the peak
; this is horribly dirty and should actually be taken care of in the ePSF - not here
; my apologies 
	sz=size(c_psf)
	;junk=max(c_psf,/nan,ind)
	;xind=ind mod sz[1]
	;yind=ind / sz[1]
	xind=where((*ptr_obj_psf).xcoords eq 0)
	yind=where((*ptr_obj_psf).ycoords eq 0)

epsf_subsamp=round(1.0/abs((*ptr_obj_psf).xcoords[1]-(*ptr_obj_psf).xcoords[0])) ; 5 normally

; anything 3 pixels away from the peak or more is zeroed here
	c_psf[0:(xind-3*epsf_subsamp)>0,*]=0
	c_psf[(xind+3*epsf_subsamp)<(sz[1]-1):*,*]=0
	c_psf[*,0:(yind-3*epsf_subsamp)>0]=0
	c_psf[*,(yind+3*epsf_subsamp)<(sz[2]-1):*]=0

;PI: should normalize the high-res PSF, not the detector sampled one - explained below
c_psf/=(total(c_psf,/nan)/ (epsf_subsamp)^2 )  ; epsf is 25 times the sampling of a detector sampled psf

; put min values in common block for fitting
c_x_vector_psf_min = min((*ptr_obj_psf).xcoords)
c_y_vector_psf_min = min((*ptr_obj_psf).ycoords)
; determine hte sampling and ploput in common block
;PI : I am not sure why this is rounded... it's rounded in my code as well.. but i have no idea why... 
; yes i do - this has to be a round number - so it just avoids numerical blips
c_sampling=round(1/( ((*ptr_obj_psf).xcoords)[1]-((*ptr_obj_psf).xcoords)[0] ))

; #####################################################
;	Determine which pixels go into the intensity array
; #####################################################

; THIS ENTIRE SECTION NEEDS TO BE REDONE
; it is sloppy and inefficient

      ;choice of pixels for the inversion
      xchoiceind=[0.]   ; these are actually coordinates not indicies of arrays
      ychoiceind=[0.]; these are actually coordinates not indicies of arrays

      for nl=0,nlam-1 do begin
        if (round(xloctab[xsi,ysi,nl])+larg lt 2048) && (round(yloctab[xsi,ysi,nl]) lt 2048) then begin
        ;avoid pairs when nlam>sdpx
            if (nl eq 0) || ~( (round(xloctab[xsi,ysi,nl-1]) eq round(xloctab[xsi,ysi,nl])) && (round(yloctab[xsi,ysi,nl-1]) eq round(yloctab[xsi,ysi,nl])))  then begin
              for clarg=-larg,larg do xchoiceind=[xchoiceind,round(xloctab[xsi,ysi,nl])+clarg>0]
              for clarg=-larg,larg do ychoiceind=[ychoiceind,round(yloctab[xsi,ysi,nl])>0]
              ;we need to keep track where the bad pixels will go in the cube for later interpolation:          
              if bad_pix_mask[round(xloctab[xsi,ysi,nl])>0,round(yloctab[xsi,ysi,nl])>0] ne 0 or finite((*dataset.currframe[0])[round(xloctab[xsi,ysi,nl])>0,round(yloctab[xsi,ysi,nl])>0]) eq 0  then $
                  cubef3Dbpix[xsi,ysi,nl]=1
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
               ;;argh, need to find which wavelength would be affected by these specific pixels
               ;; so we can interpolate that late in the code     
               xxx=round(xchoiceind[holes[chole]+larg]+((eachpixhole+1.)/(nbpixhole))*(xchoiceind[holes[chole]-larg-1]-xchoiceind[holes[chole]+larg]))
               yyy=round(ychoiceind[holes[chole]-1] - eachpixhole - 1)
               if bad_pix_mask[xxx>0,yyy>0] ne 0 or finite((*dataset.currframe[0])[xxx>0,yyy>0]) eq 0  then begin
                  
                  nlestimate=value_locate(yloctab[xsi,ysi,*],yyy)
                  cubef3Dbpix[xsi,ysi,nlestimate]=1
                  cubef3Dbpix[xsi,ysi,(nlestimate+1)<nlam]=1
               endif   
              
            endfor  
        endfor
      endif
      
; remove the bad pixels from the intensity array
; surely there is a move clever way to do this
; it does not appear to slow things down much (~1.5s our of 78s)
 
if 1 eq 1 then begin
ind=-1
; check the DQ mask for bad pixels 
for v=0,N_ELEMENTS(xchoiceind)-1 do if bad_pix_mask[xchoiceind[v],ychoiceind[v]] ne 0 or finite((*dataset.currframe[0])[xchoiceind[v],ychoiceind[v]]) eq 0  then ind=[ind,[v]]

if N_ELEMENTS(ind) gt 1 then begin
	;chop off the -1 at the beginning of the array
	ind=ind[1:*]
	remove,ind,xchoiceind,ychoiceind
	bad_pix_count+=N_ELEMENTS(ind)
endif
	
endif
;;;; END SECTION THAT NEEDS REWRITE

; get the pixel positions of the chosen wavelengths to place the ePSFs
    dx2L=reform(xloctab[xsi,ysi,*] )
    dy2L=(reform(yloctab[xsi,ysi,*] ))  


; #################################################
;	begin looping over the individual microspectra
; #################################################

; now loop over the number of chosen psfs per lenset
		for nl=0,nlam-1 do begin            
             ; get the detector sampled mlens psf for the given position
			 ; this handles the pixel phase - so only does the small offset from the integer
			psf=gpi_highres_microlens_psf_evaluate_detector_psf(xgrid, ygrid, [(dx2L[nl]-floor(dx2L[nl])) ,(dy2L[nl]-floor(dy2L[nl])) ,1.])
    	                                
            ;recenter the psf to correspond to its location onto the spectrum
			; this handles the integer shifting
            xshift=floor(dx2L[nl])-floor(dx2L[0])
            yshift=floor(dy2L[nl])-floor(dy2L[0])
            ; does this ever involve the wrapping of non-zero values to the otherside? 
            psf=padarr(psf, [dimpsfx,dimpsfy])
            psfmlens2[0,0,nl]=SHIFT(psf,xshift,yshift)
        endfor
        psfmlens4=reform(psfmlens2,dimpsfx*dimpsfy,nlam)
                  
         spectrum=reform(psfmlens4#(fltarr(nlam)+1.),dimpsfx,dimpsfy)  ;;Calcul d'un spectrum 2d 
  
		; PI: i don't understand this bit at all... Jerome will check/explain
		
		tmpx = floor(dx2L[0]) ; whole X pixel of where the first peak is
		tmpy = floor(dy2L[0]) ; whole Y pixel of where the first peak is
		; goal is to put down a dimpsf by dimpsf box 
		; where the psf array is properly aligned on top ?

        indxmin= (tmpx-(dimpsfx-1)/2) > 0 
        indxmax= (tmpx+(dimpsfx-1)/2-1) < (dim-1)
        indymin= (tmpy-(dimpsfy-1)/2) > 0
        indymax= (tmpy+(dimpsfy-1)/2-1) < (dim-1)
    
        aa = -(tmpx-(dimpsfx-1)/2)
        bb = -(tmpy-(dimpsfy-1)/2)
  
        ; for residual purpose:
		; why is this piece only a 50x50 when everything else if 51x51 ? Jerome investigating
        detector_array[indxmin:indxmax,indymin:indymax]+= $
			spectrum[indxmin+aa: indxmax+aa, indymin+bb:indymax+bb]
                
		; the aa and bb come into play here - im worried they're not correct!

; so psfmat is a 2-d matrix, the rows are the pixels of each individual wavelength psf (in 1d)
; each row is a wavelength of nlam
        psfmat=fltarr(n_elements(xchoiceind),nlam)
        for nelam=0,nlam-1 do begin
              for nbpix=0,n_elements(xchoiceind)-1 do $
                  psfmat[nbpix,nelam]=psfmlens2[xchoiceind[nbpix]+aa,ychoiceind[nbpix]+bb,nelam]
        endfor

;PI: What does this do?
; Is this checking to see if the spectrum and box goes off the detector?
;    if ((tmpx-larg) lt 0) OR  ((tmpx+larg) ge (dim-1)) OR (tmpy lt 0) OR ((tmpy+longu-1) ge (dim-1)) then flagedge=0 else flagedge=1  ; original

; if it goes off the edge we're ignoring it anyways, so might as well just set the flux to !Nan here and continue
;if ((tmpx-larg) lt 0) OR  ((tmpx+larg) ge (dim-1)) OR (tmpy lt 0) OR ((tmpy+longu-1) ge (dim-1)) then begin
;		; this spectrum runs off the detector, setting it to nan
;		cubef3D[xsi,ysi,*]=!values.f_nan
;		continue
;endif

; if it goes off the edge we're ignoring it anyways, so might as well just set the flux to !Nan here and continue
if ((tmpx-larg) lt 0) OR  ((tmpx+larg) ge (dim-1)) OR (tmpy lt 0) OR ((tmpy+dimpsfy-1) ge (dim-1)) then begin
		; this spectrum runs off the detector, setting it to nan
		cubef3D[xsi,ysi,*]=!values.f_nan
		continue
endif

		; create intensity array
        bbc=fltarr(n_elements(xchoiceind))
		for nel=0,n_elements(xchoiceind)-1 do bbc[nel]=det[xchoiceind[nel],ychoiceind[nel]]
			
		
		; create a weights array - this is the SNR of the data seen by each microlens psf
		; we can do this by using a weighted mean on the intensities
		; so SNR=sqrt(intensity)
		; but we use a weighted intensity
		; where the intensities are weighted by the psfs (which are normalized such that the integral equals 1)
	    ; noise covariance matrix
		noise_variance_lambda=fltarr(nlam)
		noise_variance=fltarr(N_ELEMENTS(xchoiceind))
		snr_arr=fltarr(nlam)
		;peak_snr_arr
		;need coadds and number of images in the stack
		nfiles=float(dataset.validframecount)
		nfiles=1
		ncoadds  = float(gpi_simplify_keyword_value(backbone->get_keyword('COADDS0', count=ct)))
		for nelam=0,nlam-1 do begin
			   tmp=0.0
			   noise=0
			   ; get the peak flux for the microlens
			   peak=max(psfmlens2[*,*,nelam],/nan)
				; this integrates the SNR - and weights it by 
				; FIGURE OUT THIS NOISE CALCULATION
				; HOW MUCH NOISE IN A PEAK!
			   for nbpix=0,n_elements(xchoiceind)-1 do tmp+=(det[xchoiceind[nbpix],ychoiceind[nbpix]]*(psfmlens2[xchoiceind[nbpix]+aa,ychoiceind[nbpix]+bb,nelam]))
		;		for nbpix=0,n_elements(xchoiceind)-1 do noise+=( sqrt((gain*det[xchoiceind[nbpix],ychoiceind[nbpix]])>0)/ $
	;											(psfmlens2[xchoiceind[nbpix]+aa,ychoiceind[nbpix]+bb,nelam]/peak))^2

			  ; now get the integrated SNR of each peak
			  snr_arr[nelam]=(gain*tmp)/(sqrt((gain*tmp)>0) + readnoise)*sqrt(nfiles*ncoadds)
;			  snr_arr[nelam]=tmp/(noise)
			  noise_variance_lambda[nelam]=( ((gain*tmp)>0) + readnoise^2 ) / (gain^2)   ; need it in ADU
        endfor

		; just get the variance of each pixel in ADU
		for nbpix=0,n_elements(xchoiceind)-1 do noise_variance[nbpix]=((det[xchoiceind[nbpix],ychoiceind[nbpix]]*gain)>0 + readnoise^2)/(gain^2) / (nfiles*ncoadds)

		; this is just to look at the pixels being used in the extraction
		if keyword_set(epsf_debug) eq 1 then begin 
		  ; want to see the pixels being used for the intensity array
		  ; don't wnat the entire 2048x2048, so just make it smaller 
          stamp=fltarr(dimpsfx,dimpsfy)
		  for nbpix=0,n_elements(xchoiceind)-1 do $
				stamp[xchoiceind[nbpix]+aa,ychoiceind[nbpix]+bb]=det[xchoiceind[nbpix],ychoiceind[nbpix]]
				; this is where you can check 
				if 0 eq 1 then begin
					loadct,0
					mag=8
					window,2,xsize=dimpsfx*mag,ysize=dimpsfy*mag,title='stamp of detector pixels'
					tvdl, stamp,min(stamp,/nan),max(stamp,/nan),/log
				endif
		endif
        
		; #################
		; Matrix inversion
		; #################
		; invert the PSF array and multiply by the intensity array to get flux
		; can currently switch between two options svd or nnls

		 ; set to 1 to use svd (fast) or 0 to use nnls (slow)
		if 1 eq 1 then begin 
			;using SVD inversion
			H=transpose(psfmat)  ; nlam by N_ELEMENTS(xchoiceind)
			; just straight inversion - no weights nor penalties
			;iHH=la_invert( transpose(H)##H,status=status) 
			;if status ne 0 then begin
				; matrix not invertable - set to nan
				; this should never happen as H is supposed to be positive definite
				; however if your intensity arary is screwed up, then your psf matrix will also be messed
				; up. This is used to derive H - so H can be messed up
			;	cubef3D[xsi,ysi,*]=!values.f_nan
			;	continue
			;endif

			;flux=iHH## transpose(H)##bbc
			

			if keyword_set(epsf_debug) eq 1 then begin
			;straight_inversion_flux=la_invert( transpose(H)##H) ## transpose(H)##bbc	
			;straight_inversion_flux_norm=straight_inversion_flux/max(straight_inversion_flux,/nan)		
	
			; waffle removal - WARNING - NO FLUX CONSERVATION
			if 0 eq 1 then begin
								; weight by the variance
				weight_arr=invert(diag_matrix(noise_variance))
				; use no weights
				;weight_arr=invert(diag_matrix(fltarr(N_ELEMENTS(noise_variance))+1))
				
				; WAFFLE REMOVAL
				; so we need to create arrays for all of the frequecies (or modes) we don't want in the flux array
				V=fltarr(nlam)#fltarr(nlam)
				tmp=fltarr(nlam)
				alpha=1.0 ; tuning factor for waffle removal
				; weight by the SNR
				alpha=1.0/(sqrt(max((bbc*3.04)>1,/nan))*sqrt(ncoadds))^2


				tmp[0]=1*alpha & tmp[1]=-1*alpha
				for qq=0, (nlam-2) do V+= (shift(tmp,qq))#(shift(tmp,qq))   
				for qq=0, (nlam-2) do V+= (shift(tmp,qq))#(shift(tmp,qq))   

				;reconstructor= la_invert( transpose(H)##H + V) ## transpose(H) 	
			
				;flux_waffle=reconstructor##bbc
				;flux_waffle_norm=flux_waffle/max(flux_waffle)
				;; now what happens when you weight by the SNR
				reconstructor= la_invert( transpose(H)##weight_arr##H + V) ## transpose(H)## weight_arr
				flux_weighted_waffle=reconstructor##bbc
				flux_weighted_waffle_norm=flux_weighted_waffle/max(flux_weighted_waffle,/nan)
				flux=flux_weighted_waffle
			endif

; ############################
; EIGENVECTOR WEIGHTING SCHEME
; ############################


			if 1 eq 1 then begin
			
			; define the matrix W
			; weight by the variance
			w=invert(diag_matrix(noise_variance))
			; no weights
			w=invert(diag_matrix(fltarr(N_ELEMENTS(noise_variance))+1))

			P=H
			I=bbc
			;random_normalization=1.0/20000  ; this is the value I don't understand -
			random_normalization=1.0/(max(snr_arr,/nan)^2) ;*(5)
			random_normalization=0
			;random_normalization=1./sqrt(total(snr_arr^2))^2  ; total SNR of the spectrum
			;1/SNR^2 of maximum pixel - cant use noise_variance because it's in ADU
			;random_normalization=1.0/(sqrt(max((bbc*3.04)>1,/nan))*sqrt(ncoadds))^2
		
			; when using the identity matrix as the measurement noise covariance matrix, 100 is good for both
			; when using the true measurement noise then 1/15000 is good for the non-flux conservation

			; find the eigenvalues/eigenvectors of the P-matrix
			eigenvalues=la_eigenql(transpose(P)##P,eigenvectors=eigenvectors,/double )
	 			
			; Create the EIGENVECTOR Penalty matrix (V)
			V=fltarr(nlam)#fltarr(nlam)
			for qq=0, N_ELEMENTS(eigenvalues)-1 do V+=transpose(eigenvectors[*,qq])##diag_matrix(1./eigenvalues[qq])##eigenvectors[*,qq]

			;define the matrix iPPV
			iPPV=invert(transpose(P)##W##P+(random_normalization)*V)
			; S = S_1 + lambda*S_0
			; lambda = (s-s_1)/S_0

			; need to define a matrix u - which is a 1-matrix of nlam elements
			ulam=transpose(fltarr(nlam)+1.0)*(nlam)
			dlambda=lambda2[3]-lambda2[1]
			ulam*=dlambda
			;also need to define another 1-matrix having the number of elements of I
			uI=transpose(fltarr(N_ELEMENTS(I))+1.0)
			; in this case we need dlambda/pixel

			S_1 = transpose(ulam) ## iPPV ## (transpose(P)##W##I) 
			S_0= transpose(ulam)##iPPV##ulam
			;S=transpose(uI)##I ; this is the integrated signal - seems to have row/column issues?
			; maybe not, F is a column vector, and I is a row vector... so the Ut's must be different...
			S=transpose(uI)##transpose(I)
			lambda=(S-S_1)/S_0

			; so the new estimate of F, which uses the weights and FORCES conservation of flux
			weighted_eigenvector_flux=iPPV ## ( transpose(P)##W##I + (lambda) ## transpose(uI) )
			weighted_eigenvector_flux_norm=weighted_eigenvector_flux/max(weighted_eigenvector_flux,/nan)
			flux=weighted_eigenvector_flux
			endif

			; comparison
			if 1 eq 1 and xsi eq sx and ysi eq sy  then begin
		;load in the 3 pixel box extraction for comparison
			tmpname='/Users/patrickingraham/GPI/data/Reduced/140510/S20140510S0241_rawspdc_3pixbox.fits'
			im_3pixbox=gpi_readfits(tmpname,priheader=priheader,header=header)-(3*sky_offset)
			; get wavelengths associated with pixels
			valx=double(xmini[xsi,ysi]-findgen(sdpx))
			lambint=wavcal[xsi,ysi,2]-wavcal[xsi,ysi,3]*(valx-wavcal[xsi,ysi,0])*(1./cos(wavcal[xsi,ysi,4]))			

			;window,2,xsize=700,ysize=400,xpos=0,ypos=50
			;plot, lambda2,weighted_eigenvector_flux_norm,yr=[-0.2,1.05],background=cgcolor('white'),color=cgcolor('black'),charsize=1.5,xtitle='wavelength [um]',ytitle='normalized intensity',xr=[1.48,1.82],/xs,thick=2 ; eigen vector weighted
			;oplot, lambda2,weighted_eigenvector_flux_norm,color=cgcolor('black'),psym=1,symsize=2
			;oplot,lambint,im_3pixbox[xsi,ysi,*]/max(im_3pixbox[xsi,ysi,*],/nan),linestyle=2,color=cgcolor('black'),thick=2
			;oplot,lambda2,straight_inversion_flux_norm,color=cgcolor('red'),thick=1,linestyle=4
		;	oplot,lambda2,flux_weighted_waffle_norm,color=cgcolor('green'),thick=2

			;pi_legend,['3-pixel box','straight inversion','Eigenvector weighting','inversion+weights+scaled waffle removal'],textcolor=cgcolor('black'),linestyle=[2,4,0,0],color=[cgcolor('black'),cgcolor('red'),cgcolor('black'),cgcolor('green')],charsize=1.2,line_frac=0.5

			window,1,xsize=700,ysize=400,xpos=0,ypos=500
			plot, lambda2,weighted_eigenvector_flux,background=cgcolor('white'),color=cgcolor('black'),charsize=1.5,xtitle='wavelength [um]',ytitle='normalized intensity',xr=[1.48,1.82],/xs,thick=2 ; eigen vector weighted
			oplot, lambda2,weighted_eigenvector_flux,color=cgcolor('black'),psym=1,symsize=2
			oplot,lambint,im_3pixbox[xsi,ysi,*],linestyle=2,color=cgcolor('black'),thick=2 ; 3 pixel box
			;oplot,lambda2,straight_inversion_flux,color=cgcolor('red'),thick=1,linestyle=4
		;	oplot,lambda2,flux_weighted_waffle,color=cgcolor('green'),thick=2

			pi_legend,['3-pixel box','straight inversion','Eigenvector weighting','inversion+weights+scaled waffle removal'],textcolor=cgcolor('black'),linestyle=[2,4,0,0],color=[cgcolor('black'),cgcolor('red'),cgcolor('black'),cgcolor('green')],charsize=1.2,line_frac=0.5

stop
endif
			; pick an inversion method
			;flux=weighted_eigenvector_flux
			;flux=straight_inversion_flux
			;flux=flux_weighted_waffle
test=where(finite(flux) eq 0,ct)
if ct ne 0 then print,'infinite flux for lenslet '+strc(xsi)+', '+strc(ysi) 
		endif ; end epsf_debug
			;SVDC, reconstructor, W_svd, U_svd, V_svd , /double
			; Compute the solution and print the result: 
	 		;flux= SVSOL(U_svd, W_svd, V_svd, bbc, /double) 
		 endif else begin
			; using NNLS inversion
			; try using only positive coefficients
			a=transpose(psfmat)  ; 13 by 95
            m=n_elements(xchoiceind) ; 95
            n=nlam ; 13
            b=bbc ; 95
			; stupid code error/formalism in nnls makes this mandatory!
		    x=fltarr(N_ELEMENTS(xchoiceind))
            w2=fltarr(nlam)
            indx=intarr(nlam+1)
			mode=1 
			rnorm=1
          	nnls, a, m, n, b, x, rnorm, w2, indx, mode
            flux=x[0:nlam-1]
			; this never flagged - so i commented it
			; if mode ne 1 then stop
		endelse ; pick a matrix inversion method
	 
	 ; put into the cube 
         cubef3D[xsi,ysi,*]=reform(flux)
		 
		          
        ; check the reconstruction?
		 if keyword_set(epsf_debug) eq 1 and 0 eq 1 then begin 
		   reconspec=fltarr(dimpsfx,dimpsfy)
           for nbpix=0,n_elements(xchoiceind)-1 do for zl=0,nlam-1 do $
				   reconspec[xchoiceind[nbpix]+aa,ychoiceind[nbpix]+bb]+=$
				   (flux[zl]*ulam[zl])*psfmlens2[xchoiceind[nbpix]+aa,ychoiceind[nbpix]+bb,zl]
          ; want to make it so we can subtract the determined spectrum from
		  ; the actual spectrum to look at residuals
		  	mag=10
			zero=where(stamp eq 0, count)
			if count gt 1 then stamp[zero]=!values.f_nan
			loadct,0
			window,4,xsize=dimpsfx*mag*3,ysize=dimpsfy*mag,title='window3 = reconspec'
			tvdl, stamp,min(stamp,/nan)>0,max(stamp,/nan),/log,position=0
			tvdl, reconspec,min(stamp,/nan)>0,max(stamp,/nan),/log,position=1
			tvdl, stamp-reconspec,/med,nsig=3,position=2
;			tvdl, (stamp-reconspec)/stamp,/med,nsig=3,position=1

		 	
stop
		 endif

endfor ; end loop over lenslet (ysi)
endfor ; end loop over lenslet (xsi)

stop

; ##################################
; Bad spaxel interpolation option
; ##################################
; this code is meant to interpolate spaxels that were heavily affected by
; bad pixels by interpolating over the ~6 surrounding pixels

; Jerome - this needs more comments
;; do you want to clean for bad pixels ?
cleaning=0
if cleaning eq 1 then begin
  print,'bad_pix_count = '+strc(bad_pix_count)
  indbp=where((cubef3dbpix eq 1) OR (cubef3d lt 0),cbp)
  szindbp=size(indbp)
  print,'total considerd bad pix = ', szindbp[2]
  
  if cbp gt 0 then begin
    print, "Interpolating bad pix..."
    cubind=array_indices(cubef3dbpix,indbp)  
    sizecubeind=size(cubind)  
     ;Result = GRID3( X, Y, Z, F, cubind[*] ) [ METHOD='NearestNeighbor' | /NEAREST_NEIGHBOR, TRIANGLES=array  [, /DEGREES ] [, DELTA=vector ] [, DIMENSION=vector ] [, FAULT_POLYGONS=vector ] [, FAULT_XY=array ] [, /GRID, XOUT=vector, YOUT=vector ] [, MISSING=value ] [, /SPHERE] [, START=vector ] 
    for bpi=0,sizecubeind[2]-1 do cubef3d[cubind[0,bpi], cubind[1,bpi], cubind[2,bpi]] = interpolatej(cubef3d, cubind[0,bpi], cubind[1,bpi], cubind[2,bpi])
  endif
endif


print,'Time to run extraction = '+strc(systime(1,/seconds)-time0)+' seconds'

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
  ;profiler,/report 
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

