;+
; NAME: gpi_img_xcorr.pro
; PIPELINE PRIMITIVE DESCRIPTION: Flexure 2D x correlation with wavecal model
;
;   This primitive uses the relevent microlense PSF and wave cal to generate a model detector image to cross correlate with a science image. 
;   The resulting output can be used as a flexure offset prior to flux extraction.
;
; INPUTS: Science image, microlens PSF, wavecal
;
; OUTPUTS: Flexure offset in xy detector coordinates.
;
; PIPELINE COMMENT: This primitive uses the relevent microlense PSF and wave cal to generate a model detector image to cross correlate with a science image. 
;   The resulting output can be used as a flexure offset prior to flux extraction.
; PIPELINE ARGUMENT: Name="range" Type="float" Default="2" Range="[0,5]" Desc="Range of cross corrleation search in pixels."
; PIPELINE ARGUMENT: Name="resolution" Type="float" Default="0.01" Range="[0,1]" Desc="Subpixel resolution of cross correlation"
; PIPELINE ARGUMENT: Name="yoff_factor" Type="float" Default="2" Range="[0,5]" Desc="Fractor of resolution to which the code converges in y_offset"
; PIPELINE ARGUMENT: Name="psf_sep" Type="float" Default="0.01" Range="[0,1]" Desc="PSF separation in pixels"
; PIPELINE ARGUMENT: Name="stopidl" Type="int" Range="[0,1]" Default="1" Desc="1: stop IDL, 0: dont stop IDL"
; PIPELINE ARGUMENT: Name="x_off" Type="float" Default="0" Range="[-5,5]" Desc="initial guess for large offsets"
; PIPELINE ARGUMENT: Name="y_off" Type="float" Default="0" Range="[-5,5]" Desc="initial guess for large offsets"
; PIPELINE ARGUMENT: Name="badpix" Type="float" Default="0" Range="[0,1]" Desc="Weight by bad pixel map?"
; 
; 
; where in the order of the primitives should this go by default?
; PIPELINE ORDER: 5.0
;
; pick one of the following options for the primitive type:
; PIPELINE NEWTYPE: SpectralScience
;
; HISTORY:
;    Began 2014-01-13 by Zachary Draper
;-  

;-----------------------------
;

function gpi_img_xcorr, DataSet, Modules, Backbone
; enforce modern IDL compiler options:
compile_opt defint32, strictarr, logical_predicate

; don't edit the following line, it will be automatically updated by subversion:
primitive_version= '$Id$' ; get version from subversion to store in header history

calfiletype=''   ; set this to some non-null value e.g. 'dark' if you want to load a cal file.

; the following line sources a block of code common to all primitives
; It loads some common blocks, records the primitive version in the header for
; history, then if calfiletype is not blank it queries the calibration database
; for that file, and does error checking on the returned filename.
@__start_primitive
suffix='' 		 ; set this to the desired output filename suffix

 	if tag_exist( Modules[thisModuleIndex],"range") then range=float(Modules[thisModuleIndex].range) else range=2.0
	if tag_exist( Modules[thisModuleIndex],"resolution") then resolution=float(Modules[thisModuleIndex].resolution) else resolution=0.01

	if tag_exist( Modules[thisModuleIndex],"psf_sep") then steps=float(Modules[thisModuleIndex].psf_sep) else steps=0.01

	;stop idl session
	if tag_exist( Modules[thisModuleIndex],"stopidl") then stopidl=long(Modules[thisModuleIndex].stopidl) else save=0

	if tag_exist(Modules[thisModuleIndex],"x_off") then x_off=float(Modules[thisModuleIndex].x_off) else x_off=0
	if tag_exist(Modules[thisModuleIndex],"y_off") then y_off=float(Modules[thisModuleIndex].y_off) else y_off=0

	img = *dataset.currframe

	;define the common wavelength vector with the IFSFILT keyword:
  	filter = gpi_simplify_keyword_value(backbone->get_keyword('IFSFILT', count=ct))
  	if (filter eq '') then return, error('FAILURE ('+functionName+'): IFSFILT keyword not found.') 

	;run badpixel suppresion
	if tag_exist(Modules[thisModuleIndex],"badpix") then $
		badpix=float(Modules[thisModuleIndex].badpix) else badpix=0

	if (badpix eq 1) then begin
		badpix_file = (backbone_comm->getgpicaldb())->get_best_cal_from_header('badpix',*(dataset.headersphu)[numfile],*(dataset.headersext)[numfile])
		badpix = gpi_READFITS(badpix_file)
		ones = bytarr(2048,2048)+1
		badpix=ones-badpix
	endif

  	nlens=(size(wavcal))[1]       ;pixel sidelength of final datacube (spatial dimensions) 	
  	;;error handle if readwavcal or not used before
  	if (nlens eq 0)  then $
		return, error('FAILURE ('+functionName+'): Failed to load wavelength calibration data prior to calling this primitive.') 

	; get mlens PSF filename
	if (total(size(mlens_file)) eq 0) then $
		return, error('FAILURE ('+functionName+'): Failed to load microlens PSF data prior to calling this primitive.') 
	
	;free optimization knobs
	xsize=16			;spectra sub image size
	ysize=64			;	extracted for lsqr

	;lens_arr=[[46,175],[178,226],[85,116],[210,170]] 	; center lens locations for sub image extraction.
	;lens_arr=[[85,116],[210,170],[167,87],[114,190]] 
	lens_arr=[[85,116],[210,170],[46,175],[178,200]]
	; make a function to determine satellite spot locations for beter performance?

	blank2 = fltarr(xsize,ysize)

	;get filter wavelength range
	cwv=get_cwv(filter)	
	gpi_lambda=cwv.lambda	
	para=cwv.CommonWavVect

	wcal_off = [0,0,0,0,0]
	del_lam_best=0
	del_x_best=0
	del_theta_best=0

	;extract stellar spectra in order to match shape of microspectra 
	;	add more extractions to make an average? tune to lenslet at satellite spots or edge of choronograph?
	exe_tst = execute("resolve_routine,'gpi_lsqr_mlens_extract_dep',/COMPILE_FULL_FILE")

	n=0
	b=0
	a=0
	xsft=resolution
	xsft_sav=xsft
	ysft=resolution
	range_start=range
	stddev_mem=[0]
	y_off_mem=[0]
	flux_mem=[0]

	;supress all bad pixels 
	img=img*badpix

	while (abs(ysft) gt (3*resolution)) or (abs(xsft_sav) gt (resolution/2)) do begin

img_spec_ext_amoeba,lens_arr[0,0],lens_arr[1,0],img,mlens,wavcal,spec,spec_img,mic_img,del_lam_best,del_x_best,del_theta_best,x_off,y_off,wcal_off,para,badpix,resid=1,micphn=0,iter=0	
img_spec_ext_amoeba,lens_arr[0,0],lens_arr[1,0],img,mlens,wavcal,spec2,spec_img2,mic_img2,del_lam_best+0.66,del_x_best,del_theta_best,x_off,y_off,wcal_off2,para,badpix,resid=1,micphn=0,iter=0
img_spec_ext_amoeba,lens_arr[0,0],lens_arr[1,0],img,mlens,wavcal,spec3,spec_img2,mic_img2,del_lam_best-0.66,del_x_best,del_theta_best,x_off,y_off,wcal_off2,para,badpix,resid=1,micphn=0,iter=0
		hr_spec=combine_spec(spec,spec2,spec3)
		lens_spec = interpol(hr_spec[*,1],hr_spec[*,0],gpi_lambda)

img_spec_ext_amoeba,lens_arr[0,1],lens_arr[1,1],img,mlens,wavcal,spec,spec_img,mic_img,del_lam_best,del_x_best,del_theta_best,x_off,y_off,wcal_off,para,badpix,resid=1,micphn=0,iter=0	
img_spec_ext_amoeba,lens_arr[0,1],lens_arr[1,1],img,mlens,wavcal,spec2,spec_img2,mic_img2,del_lam_best+0.66,del_x_best,del_theta_best,x_off,y_off,wcal_off2,para,badpix,resid=1,micphn=0,iter=0
img_spec_ext_amoeba,lens_arr[0,1],lens_arr[1,1],img,mlens,wavcal,spec3,spec_img2,mic_img2,del_lam_best-0.66,del_x_best,del_theta_best,x_off,y_off,wcal_off2,para,badpix,resid=1,micphn=0,iter=0
		hr_spec=combine_spec(spec,spec2,spec3)
		lens_spec2 = interpol(hr_spec[*,1],hr_spec[*,0],gpi_lambda)

img_spec_ext_amoeba,lens_arr[0,2],lens_arr[1,2],img,mlens,wavcal,spec,spec_img,mic_img,del_lam_best,del_x_best,del_theta_best,x_off,y_off,wcal_off,para,badpix,resid=1,micphn=0,iter=0	
img_spec_ext_amoeba,lens_arr[0,2],lens_arr[1,2],img,mlens,wavcal,spec2,spec_img2,mic_img2,del_lam_best+0.66,del_x_best,del_theta_best,x_off,y_off,wcal_off2,para,badpix,resid=1,micphn=0,iter=0
img_spec_ext_amoeba,lens_arr[0,2],lens_arr[1,2],img,mlens,wavcal,spec3,spec_img2,mic_img2,del_lam_best-0.66,del_x_best,del_theta_best,x_off,y_off,wcal_off2,para,badpix,resid=1,micphn=0,iter=0
		hr_spec=combine_spec(spec,spec2,spec3)
		lens_spec3 = interpol(hr_spec[*,1],hr_spec[*,0],gpi_lambda)		

img_spec_ext_amoeba,lens_arr[0,3],lens_arr[1,3],img,mlens,wavcal,spec,spec_img,mic_img,del_lam_best,del_x_best,del_theta_best,x_off,y_off,wcal_off,para,badpix,resid=1,micphn=0,iter=0	
img_spec_ext_amoeba,lens_arr[0,3],lens_arr[1,3],img,mlens,wavcal,spec2,spec_img2,mic_img2,del_lam_best+0.66,del_x_best,del_theta_best,x_off,y_off,wcal_off2,para,badpix,resid=1,micphn=0,iter=0
img_spec_ext_amoeba,lens_arr[0,3],lens_arr[1,3],img,mlens,wavcal,spec3,spec_img2,mic_img2,del_lam_best-0.66,del_x_best,del_theta_best,x_off,y_off,wcal_off2,para,badpix,resid=1,micphn=0,iter=0
		hr_spec=combine_spec(spec,spec2,spec3)
		lens_spec4 = interpol(hr_spec[*,1],hr_spec[*,0],gpi_lambda)

			;off1=total(lens_spec)/total(lens_spec2)
			;off2=total(lens_spec)/total(lens_spec3)
			;off3=total(lens_spec)/total(lens_spec4)

			;lens_spec2=lens_spec2*off1
			;lens_spec3=lens_spec3*off2
			;lens_spec4=lens_spec4*off3

			;window,0
			;plot,spec1[0,*],spec1[1,*]
			;oplot,spec2[0,*],spec2[1,*]
			;oplot,spec3[0,*],spec3[1,*]
			;oplot,spec4[0,*],spec4[1,*]
	
			;lens_spec=fltarr(n_elements(gpi_lambda))+1
			;lens_spec[0:1]=0
			;lens_spec[n_elements(gpi_lambda)-2:*]=0
			;lens_spec2=lens_spec
			;lens_spec3=lens_spec
			;lens_spec4=lens_spec

			spec_flx_all=[[lens_spec],[lens_spec2],[lens_spec3],[lens_spec4]]

			spec_lam = gpi_lambda

			;stop

			mdl_full = fltarr(xsize*4,ysize*1)
			sub_full = fltarr(xsize*4,ysize*1)

			for z=0,3 do begin

				spec_flx=spec_flx_all[*,z]

				x_lens_cen=lens_arr[0,z]
				y_lens_cen=lens_arr[1,z]
				;get psf positions from wave cal

				sub_mdl_img=make_mdl_img(x_lens_cen,y_lens_cen,wavcal,para,steps,x_off,y_off,blank2,xsize,ysize,img,mlens,spec_flx,spec_lam,del_x_best)

				;stack sub images length wise
				mdl_full[z*xsize:(z+1)*xsize-1,0:ysize-1]=sub_mdl_img[*,*,0]/total(sub_mdl_img[*,*,0])
				sub_full[z*xsize:(z+1)*xsize-1,0:ysize-1]=sub_mdl_img[*,*,1]

				twod_img_corr,sub_mdl_img[*,*,1],sub_mdl_img[*,*,0],range,resolution,xsft,ysft,corr
				print,xsft,ysft


		window,0
		plot,spec_lam,spec_flx
		;Ar
		vline,1.5050
		vline,1.6945
		vline,1.7919
		vline,1.7449

			endfor

			;mdl_full=mdl_full-median(mdl_full)
			;non-negative model
			ids = where_xyz(mdl_full lt 0)
			if ids[0] ne -1 then mdl_full[ids]=0

			mdl_full_save = mdl_full
			twod_img_corr,sub_full,mdl_full,range,resolution/4.00,xsft,ysft,corr
			;corr=correl_images(mdl_full,sub_full,magnification=resolution)
			;corrmat_analyze, corr, xsft, ysft, magnification=resolution
			;stop
			print,xsft,ysft
		;stop
			x_off=x_off+xsft

		range=min([range_start,max(abs([ysft,xsft]))])
		range=max([range,7*resolution])
		;range=range_start

		ysft=ysft
		y_off=y_off+ysft

		print,x_off,y_off

		xsft_sav=xsft

		sdev=stddev(sub_full-(total(sub_full)/total(mdl_full))*mdl_full)
		stddev_mem=[stddev_mem,sdev]
		y_off_mem=[y_off_mem,y_off]
		flux_mem=[flux_mem,total(spec_flx_all)]
		;trust large x offset first and ignore first y offset.
		if (n lt 1) then begin 
			ysft=0
			xsft_sav=resolution
			stddev_mem=[sdev]
			y_off_mem=[y_off]
			flux_mem=[total(spec_flx_all)]
		endif
		n=n+1

		if (n eq 4) then begin 
			stop
		endif
		;stop
		window,1
		imdisp,corr,/axis
		window,2
		imdisp,mdl_full,/axis
		window,3
		;imdisp,sub_full-(total(sub_full)/total(mdl_full))*mdl_full
		print,sdev
		print,total(spec_flx_all)



		tstimg=fltarr(3*xsize,ysize)
		data = sub_mdl_img[*,*,1]*(total(sub_mdl_img[*,*,0])/total(sub_mdl_img[*,*,1]))
		tstimg[0:xsize-1,0:ysize-1] = data
		model = sub_mdl_img[*,*,0]
		tstimg[xsize:(2*xsize)-1,0:ysize-1] = model
		residual = sub_mdl_img[*,*,1]-(total(sub_mdl_img[*,*,1])/total(sub_mdl_img[*,*,0]))*sub_mdl_img[*,*,0]
		tstimg[(2*xsize):(3*xsize)-1,0:ysize-1] = residual
		imdisp,tstimg,/axis

		;cgimage, residual, /keep_aspect_ratio, /axis    
		;cgColorbar, /fit, /vertical, position=[0.10, 0.90, 0.90, 0.91]
				
		;stop
	endwhile


	backbone->set_keyword,'HISTORY',functionname+ " Flexure determined by 2D xcorrelation with wavecal"
	;fxaddpar not working to add keyword ??
	;backbone->set_keyword,'FLEXURE_X',xsft
	;backbone->set_keyword,'FLEXURE_Y',ysft

	;itime = backbone->get_keyword('ITIME')

	backbone->Log, "Flexure offset determined to be; X: "+string(x_off)+" Y: "+string(y_off)

@__end_primitive

end
