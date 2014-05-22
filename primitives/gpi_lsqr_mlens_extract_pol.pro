;+
; NAME: gpi_lsqr_mlens_extract_pol.pro
; PIPELINE PRIMITIVE DESCRIPTION: Assemble Polarization Datacube (Lsqr, microlens psf) 
;
;	This primitive will extract flux from a 2D detector image of Wollaston spots into a GPI polarization cube using a least-square, matrix inversion algorithm and microlenslet PSFs.  
;	Optionally can produce a residual detector image, solve for microphonics, and iterate the polcal solution to find a minimum residual.
;	Ideally run in parrallel enviroment.
;
; INPUTS: 2D detector image, polcal, microlens PSF reference.
;
; OUTPUTS: GPI datacube
;
; PIPELINE COMMENT: This primitive will extract flux from a 2D detector image into a GPI polarization cube using a least-square algorithm and microlenslet PSFs. Optionally can produce a residual detector image, solve for microphonics, and iterate the polcal solution to find a minimum residual.
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="1" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="stopidl" Type="int" Range="[0,1]" Default="0" Desc="1: stop IDL, 0: dont stop IDL"
; PIPELINE ARGUMENT: Name="np" Type="float" Default="2" Range="[0,100]" Desc="Number of processors to use in reduction (double check enviroment before running)"
; PIPELINE ARGUMENT: Name="resid" Type="int" Default="1" Range="[0,1]" Desc="Save residual detector image?"
; PIPELINE ARGUMENT: Name="micphn" Type="int" Default="0" Range="[0,1]" Desc="Solve for microphonics?"
; PIPELINE ARGUMENT: Name="iter" Type="int" Default="1" Range="[0,1]" Desc="Run iterative solver of polcal?"
; PIPELINE ARGUMENT: Name="x_off" Type="float" Default="0" Range="[-5,5]" Desc="Offset from wavecal in x pixels"
; PIPELINE ARGUMENT: Name="y_off" Type="float" Default="0" Range="[-5,5]" Desc="Offset from wavecal in y pixels"
;
; 
; where in the order of the primitives should this go by default?
; PIPELINE ORDER: 5.0
;
; pick one of the following options for the primitive type:
; PIPELINE NEWTYPE: PolarimetricScience
;
; HISTORY:
;    Began 2014-02-17 by Zachary Draper
;-  

;--------------------------------------------------
;MAIN FUNCTION

function gpi_lsqr_mlens_extract_pol, DataSet, Modules, Backbone
compile_opt defint32, strictarr, logical_predicate

; don't edit the following line, it will be automatically updated by subversion:
primitive_version= '$Id$' ; get version from subversion to store in header history

calfiletype=''   ; set this to some non-null value e.g. 'dark' if you want to load a cal file.

@__start_primitive
suffix='-podc' 		 ; set this to the desired output filename suffix

	;processors
 	if tag_exist( Modules[thisModuleIndex], "np") then np=float(Modules[thisModuleIndex].np) else np=2

	;keywords for solver
	keywords=''
	if tag_exist(Modules[thisModuleIndex],"resid") then resid=Modules[thisModuleIndex].resid else resid=0
	keywords=keywords+',resid='+string(resid)

	if tag_exist(Modules[thisModuleIndex],"micphn") then micphn=Modules[thisModuleIndex].micphn else micphn=0
	keywords=keywords+',micphn='+string(micphn)

	if tag_exist(Modules[thisModuleIndex],"iter") then iter=Modules[thisModuleIndex].iter else iter=0 
	keywords=keywords+',iter='+string(iter)

	;flexure offset in xy pixel detector coordiantes
  	if (n_elements(xsft) eq 0) or (n_elements(ysft) eq 0) then begin
     		backbone->Log,'Flexure shift not determined prior to flux extraction, using primitive parameters instead.' 
		if tag_exist(Modules[thisModuleIndex],"x_off") then xsft=float(Modules[thisModuleIndex].x_off) else xsft=0
		if tag_exist(Modules[thisModuleIndex],"y_off") then ysft=float(Modules[thisModuleIndex].y_off) else ysft=0
	endif else begin
		backbone->Log,"Using prior flexure offsets; X: "+string(xsft)+" Y: "+string(ysft)
	endelse

	;save final output
	if tag_exist( Modules[thisModuleIndex], "save") then save=long(Modules[thisModuleIndex].save) else save=0

	;stop idl session
	if tag_exist( Modules[thisModuleIndex], "stopidl") then stopidl=long(Modules[thisModuleIndex].stopidl) else stopidl=0

	;define the common wavelength vector with the IFSFILT keyword:
  	filter = gpi_simplify_keyword_value(backbone->get_keyword('IFSFILT', count=ct))
  	if (filter eq '') then return, error('FAILURE ('+functionName+'): IFSFILT keyword not found.') 

	;run badpixel suppresion
	if tag_exist(Modules[thisModuleIndex],"badpix") then $
		badpix=float(Modules[thisModuleIndex].badpix) else badpix=0

	if (badpix eq 1) then begin
		badpix_file = (backbone_comm->getgpicaldb())->get_best_cal_from_header('badpix',*(dataset.headersphu)[numfile],*(dataset.headersext)[numfile])
		if ((size(badpix_file))[1] eq 0) then $
			return, error('FAILURE ('+functionName+'): Failed to find badpixel map, set to 0 or make badpixel map prior.') 
		badpix = gpi_READFITS(badpix_file)
		ones = bytarr(2048,2048)+1
		badpix=ones-badpix
	endif
	
  	;;error handle if readpolcal or not used before
	if ~(keyword_set(polcal.coords)) then return, error("You must use Load Polarization Calibration before Assemble Polarization Cube")

	; get 2d detector image put into shared memory
	img=*(dataset.currframe[0])
	szim=size(img)
	;shmmap,'imshr',type=szim[0],szim[1],szim[2]
	;imshr=shmvar('imshr')
	;imshr[0,0]=img
	
	;The Data quality array
	dqarr=*(dataset.currdq)

  nlens=281;szim[1] ;The number of lenslets
  
	;setup memory for model images, wavecal offsets, and pol cube data
	pcal_off_cube=fltarr(nlens,nlens,3)
	;shmmap,'wcal_off_cube',type=4,nlens,nlens,7,/sysv
	;wcal_off_cube=shmvar('wcal_off_cube')
	pcal_off_cube[0,0,0]=pcal_off_cube

	pol_cube=fltarr(szim[1],szim[2])
	;shmmap,'spec_cube',type=4,szim[1],szim[2],/sysv
	;spec_cube=shmvar('spec_cube')
	pol_cube[0,0]=pol_cube

	mic_cube_pol=fltarr(szim[1],szim[2])
	;shmmap,'mic_cube',type=4,szim[1],szim[2],/sysv
	;mic_cube=shmvar('mic_cube')
	mic_cube_pol[0,0]=mic_cube_pol

	gpi_pol=fltarr(nlens,nlens,2)
	shmmap,'gpi_pol',type=4,nlens,nlens,2,/sysv
	gpi_pol=shmvar('gpi_pol')
	gpi_pol[0,0,0]=gpi_pol
  
  ;Copied from the spectral mode equivalent
  id = where_xyz(finite(reform(polcal.spotpos[0,*,*,0])),XIND=xarr,YIND=yarr)
  nlens_tot = n_elements(xarr)
  lens = [transpose(xarr),transpose(yarr)]

  ;randomly sort lenslet list to equalize job time.
  lens=lens[*,sort(randomu(seed,n_elements(lens)/2))]

	pcal = polcal.spotpos
	del_x=0
	del_y=0

	;if lmgr(/runtime) and np gt 1 then begin
	if (0 eq 1) then begin
		backbone->Log, "Cannot use parallelization in IDL runtime. Switching to single thread only."
		tst = call_function('img_ext_pol_para',0,(nlens_tot-1),0,img,pcal_off_cube,pol_cube,mic_cube_pol,gpi_pol,pcal,mlens_file,resid=resid,micphn=micphn,iter=iter,del_x=del_x,del_y=del_y,x_off=xsft,y_off=ysft,lens=lens,badpix=badpix)

	endif else begin
		; start bridges from utils function
		oBridge=gpi_obridgestartup(nbproc=np)
		
		for j=0,np-1 do begin
			oBridge[j]->Setvar,'img',img
			oBridge[j]->Setvar,'pol_cube',pol_cube
			oBridge[j]->Setvar,'mic_cube_pol',mic_cube_pol
			oBridge[j]->Setvar,'gpi_pol',gpi_pol
			oBridge[j]->Setvar,'pcal_off_cube',pcal_off_cube
			oBridge[j]->Setvar,'pcal',pcal
			oBridge[j]->Setvar,'lens',lens
			oBridge[j]->Setvar,'badpix',badpix

			cut1 = floor((nlens_tot/np)*j)
			cut2 = floor((nlens_tot/np)*(j+1))-1

			oBridge[j]->Execute, strcompress('wait,'+string(5),/remove_all)
			oBridge[j]->Execute, "print,'loading PSFs'"
			
			oBridge[j]->Execute, ".r "+gpi_get_directory('GPI_DRP_DIR')+"/utils/gpi_lsqr_mlens_extract_pol_dep.pro"

			process=strcompress('img_ext_pol_para,'+string(cut1)+','+string(cut2)+','+string(j)+',img,pcal_off_cube,pol_cube,mic_cube_pol,gpi_pol,pcal,"'+mlens_file+'",del_x='+string(del_x)+',del_y='+string(del_y)+',x_off='+string(xsft)+',y_off='+string(ysft)+',lens=lens,badpix=badpix'+keywords,/remove_all)

			oBridge[j]->Execute, "print,'"+process+"'"
			oBridge[j]->Execute, process, /nowait		

		endfor
	  
		waittime=10
		  ;check status if finish kill bridges
		backbone->Log, 'Waiting for jobs to complete...'
	  	status=intarr(np)
	  	statusinteg=1
	  	wait,1
	  	t2start=systime(/seconds)
	  	while statusinteg ne 0 do begin
	   		t2=systime(/seconds)
	   		if (round(t2-t2start))mod(300.) eq 0 then print,'Processors have been working for = ',round((t2-t2start)/60),'min'
	   			for i=0,np-1 do begin
	    				status[i] = oBridge[i]->Status()
	   			endfor
	   		print,status
	   		statusinteg=total(status)
	   		wait,waittime
	  	endwhile
	  	backbone->Log, 'Job status:'+string(status)

		gpi_obridgekill,oBridge
	endelse

	dir = gpi_get_directory('GPI_REDUCED_DATA_DIR')
	;recover from scratch since shared memory doesnt work yet
	for n=0,np-1 do begin
		exe_tst = execute(strcompress('restore,"'+dir+'gpi_pol_'+string(n)+'.sav"',/remove_all))
		exe_tst = execute(strcompress('gpi_pol=gpi_pol+gpi_pol_'+string(n),/remove_all))
		;exe_tst = execute('file_delete,"'+dir+'gpi_cube_'+strcompress(string(n)+'.sav"',/remove_all))
		if (resid eq 1) then begin
			exe_tst = execute(strcompress('restore,"'+dir+'pol_cube_'+string(n)+'.sav"',/remove_all))
			exe_tst = execute(strcompress('pol_cube=pol_cube+pol_cube_'+string(n),/remove_all))
			;exe_tst = execute('file_delete,"'+dir+'spec_cube_'+strcompress(string(n)+'.sav"',/remove_all))
      			if (micphn eq 1) then begin
				exe_tst = execute(strcompress('restore,"'+dir+'mic_cube_pol_'+string(n)+'.sav"',/remove_all))
      				exe_tst = execute(strcompress('mic_cube=mic_cube+mic_cube_pol_'+string(n),/remove_all))
       				;exe_tst = execute('file_delete,"'+dir+'mic_cube_'+strcompress(string(n)+'.sav"',/remove_all))
			endif
		endif
		if (iter eq 1) then begin
			exe_tst = execute(strcompress('restore,"'+dir+'pcal_off_cube_'+string(n)+'.sav"',/remove_all))
			exe_tst = execute(strcompress('pcal_off_cube=pcal_off_cube+pcal_off_cube_'+string(n),/remove_all))
			;exe_tst = execute('file_delete,"'+dir+'wcal_off_cube_'+strcompress(string(n)+'.sav"',/remove_all))
		endif
	endfor

	;Save residual
	if (resid eq 1) then begin
		residual_pol=img-pol_cube
		if (micphn eq 1) then residual_pol=residual_pol-mic_pol
		*(dataset.currframe)=residual_pol
		b_Stat = save_currdata( Dataset,  Modules[thisModuleIndex].OutputDir, 'residual_pol', SaveData=residual, SaveHead=Header)
	endif	

	;Save pcal offsets
	if (iter eq 1) then begin
	*(dataset.currframe)=pcal_off_cube
		b_Stat = save_currdata( Dataset,  Modules[thisModuleIndex].OutputDir, 'pcaloff', SaveData=pcal_off_cube, SaveHead=Header)
	endif		
	
	;; Update FITS header 

	;; Update WCS with RA and Dec information As long as it's not a TEL_SIM image
	sz = size(gpi_pol)    
	if ~strcmp(string(backbone->get_keyword('OBJECT')), 'TEL_SIM') then gpi_update_wcs_basic,backbone,imsize=sz[1:2]

	backbone->set_keyword, 'COMMENT', "  For specification of Stokes WCS axis, see ",ext_num=1
	backbone->set_keyword, 'COMMENT', "  Greisen & Calabretta 2002 A&A 395, 1061, section 5.4",ext_num=1

	backbone->set_keyword, "NAXIS",    sz[0], /saveComment
	backbone->set_keyword, "NAXIS1",   sz[1], /saveComment, after='NAXIS'
	backbone->set_keyword, "NAXIS2",   sz[2], /saveComment, after='NAXIS1'
	backbone->set_keyword, "NAXIS3",   sz[3], /saveComment, after='NAXIS2'

	backbone->set_keyword, "FILETYPE", "Stokes Cube", "What kind of IFS file is this?"
	backbone->set_keyword, "WCSAXES",  3, "Number of axes in WCS system"
	backbone->set_keyword, "CTYPE3",   "STOKES",     "Polarization"
	backbone->set_keyword, "CUNIT3",   "N/A",       "Polarizations"
	backbone->set_keyword, "CRVAL3",   -6, " Stokes axis: image 0 is Y parallel, 1 is X parallel "

	backbone->set_keyword, "CRPIX3", 1.,         "Reference pixel location" ;;ds - was 0, but should be 1, right?
	backbone->set_keyword, "CD3_3",  1, "Stokes axis: images 0 and 1 give orthogonal polarizations." ; 

	*(dataset.currframe)=gpi_pol

	;unmap shared mem
	;SHMUNMAP, 'wcal_off_cube'
	;SHMUNMAP, 'spec_cube'
	;SHMUNMAP, 'mic_cube'
	;SHMUNMAP, 'gpi_cube'

	;  Clean up variables before reloading them
  	gpi_pol[*]=0
  	pol_cube[*]=0
  	mic_cube_pol[*]=0
  	pcal_off_cube[*]=0
	
@__end_primitive

end
