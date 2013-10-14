;+
; NAME: gpi_Measure_Contrast
; PIPELINE PRIMITIVE DESCRIPTION: Measure Contrast
;
;   TODO - should we revise this to call the same contrast measurement backend
;   as GPItv? 
;
; OUTPUTS: 
; 	Contrast datacube, plot of contrast curve
;
;
; PIPELINE COMMENT: Measure the contrast. Save as PNG or FITS table.
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="0" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="Display" Type="int" Range="[-1,100]" Default="0" Desc="Window number to display in.  -1 for no display."
; PIPELINE ARGUMENT: Name="SaveProfile" Type="string" Default="" Desc="Save radial profile to filename as FITS (blank for no save, dir name for default naming, AUTO for auto full path)"
; PIPELINE ARGUMENT: Name="SavePNG" Type="string" Default="" Desc="Save plot to filename as PNG (blank for no save, dir name for default naming, AUTO for auto full path) "
; PIPELINE ARGUMENT: Name="contrsigma" Type="float" Range="[0.,20.]" Default="5." Desc="Contrast sigma limit"
; PIPELINE ARGUMENT: Name="slice" Type="int" Range="[-1,50]" Default="0" Desc="Slice to plot. -1 for all"
; PIPELINE ARGUMENT: Name="DarkHoleOnly" Type="int" Range="[0,1]" Default="1" Desc="0: Plot profile in dark hole only; 1: Plot outer profile as well."
; PIPELINE ARGUMENT: Name="contr_yunit" Type="int" Range="[0,2]" Default="0" Desc="0: Standard deviation; 1: Median; 2: Mean."
; PIPELINE ARGUMENT: Name="contr_xunit" Type="int" Range="[0,1]" Default="0" Desc="0: Arcsec; 1: lambda/D."
; PIPELINE ARGUMENT: Name="yscale" Type="int" Range="[0,1]" Default="0" Desc="0: Auto y axis scaling; 1: Manual scaling."
; PIPELINE ARGUMENT: Name="contr_yaxis_type" Type="int" Range="[0,1]" Default="1" Desc="0: Linear; 1: Log"
; PIPELINE ARGUMENT: Name="contr_yaxis_min" Type="float" Range="[0.,1.]" Default="0.00000001" Desc="Y axis minimum"
; PIPELINE ARGUMENT: Name="contr_yaxis_max" Type="float" Range="[0.,1.]" Default="1." Desc="Y axis maximum"
; PIPELINE ORDER: 2.7
; PIPELINE NEWTYPE: SpectralScience,PolarimetricScience
; PIPELINE TYPE: ALL
;
; HISTORY:
; 	initial version imported GPItv (with definition of contrast corrected) - JM
;-
function gpi_measure_contrast, DataSet, Modules, Backbone

primitive_version= '$Id$' ; get version from subversion to store in header history
@__start_primitive

cube = *(dataset.currframe[0])
band = gpi_simplify_keyword_value(backbone->get_keyword('IFSFILT', count=ct))
;;error handle if extractcube not used before
if ((size(cube))[0] ne 3) || (strlen(band) eq 0)  then $
   return, error('FAILURE ('+functionName+'): Datacube or filter not defined. Use "Assemble Datacube" before this one.')   
cwv = get_cwv(band,spectralchannels=(size(cube,/dim))[2])
cwv = cwv.lambda

;;error handle if sat spots haven't been found
tmp = backbone->get_keyword("SATSMASK", ext_num=1, count=ct)
if ct eq 0 then $
   return, error('FAILURE ('+functionName+'): SATSMASK undefined.  Use "Measure satellite spot locations" before this one.')

;;grab satspots 
goodcode = hex2bin(tmp,(size(cube,/dim))[2])
good = long(where(goodcode eq 1))
cens = fltarr(2,4,(size(cube,/dim))[2])
for s=0,n_elements(good) - 1 do begin 
   for j = 0,3 do begin 
      tmp = fltarr(2) + !values.f_nan 
      reads,backbone->get_keyword('SATS'+strtrim(long(good[s]),2)+'_'+strtrim(j,2),ext_num=1),tmp,format='(F7," ",F7)' 
      cens[*,j,good[s]] = tmp 
   endfor 
endfor

;;error handle if sat spots haven't been found
tmp = backbone->get_keyword("SATSWARN", ext_num=1, count=ct)
if ct eq 0 then $
   return, error('FAILURE ('+functionName+'): SATSWARN undefined.  Use "Measure satellite spot fluxes" before this one.')

;;grab sat fluxes
warns = hex2bin(tmp,(size(cube,/dim))[2])
satflux = fltarr(4,(size(cube,/dim))[2])
for s=0,n_elements(good) - 1 do begin
   for j = 0,3 do begin 
      satflux[j,good[s]] = backbone->get_keyword('SATF'+strtrim(long(good[s]),2)+'_'+strtrim(j,2),ext_num=1) 
   endfor 
endfor

;;get grid fac
apodizer = backbone->get_keyword('APODIZER', count=ct)
if strcmp(apodizer,'UNKNOWN',/fold_case) then begin
   val = backbone->get_keyword('OCCULTER', count=ct)
   if ct ne 0 then begin
      res = stregex(val,'FPM_([A-Za-z])',/extract,/subexpr)
      if res[1] ne '' then apodizer = res[1]
   endif
endif 
gridfac = gpi_get_gridfac(apodizer)
if ~finite(gridfac) then return, error('FAILURE ('+functionName+'): Could not match apodizer.')

;;get user inputs
contrsigma = float(Modules[thisModuleIndex].contrsigma)
slice = fix(Modules[thisModuleIndex].slice)
doouter = 1 - fix(Modules[thisModuleIndex].DarkHoleOnly)
wind = fix(Modules[thisModuleIndex].Display)
radialsave = Modules[thisModuleIndex].SaveProfile
pngsave = Modules[thisModuleIndex].SavePNG
contr_yunit = fix(Modules[thisModuleIndex].contr_yunit)
contr_xunit = fix(Modules[thisModuleIndex].contr_xunit)
contr_yaxis_type = fix(Modules[thisModuleIndex].contr_yaxis_type)
contr_yaxis_min=float(Modules[thisModuleIndex].contr_yaxis_min)
contr_yaxis_max=float(Modules[thisModuleIndex].contr_yaxis_max)
yscale = fix(Modules[thisModuleIndex].yscale)

;;we're going to do the copsf for all the slices
copsf = cube
for j = 0, (size(cube,/dim))[2]-1 do begin
   tmp = where(good eq j,ct)
   if ct eq 1 then copsf[*,*,j] = copsf[*,*,j]/((1./gridfac)*mean(satflux[*,j])) else $
      copsf[*,*,j] = !values.f_nan
endfor

;;set proper scale unit
if contr_yunit eq 0 then sclunit = contrsigma else sclunit = 1d

if (wind ne -1) || (radialsave ne '') || (pngsave ne '') then begin
   ;;determine which we are plotting
   if slice eq -1 then inds = good else begin
      inds = slice
      tmp = where(good eq slice,ct)
      if ct eq 0 then $
         return, error('FAILURE ('+functionName+'): SATSPOTS not found for requested slice.')
   endelse

   xrange = [1e12,-1e12]
   yrange = [1e12,-1e12]
   contrprof = ptrarr(n_elements(inds),/alloc)
   asecs = ptrarr(n_elements(inds),/alloc)

   for j = 0, n_elements(inds)-1 do begin
      ;; get the radial profile desired
      case contr_yunit of
         0: radial_profile,copsf[*,*,inds[j]],cens[*,*,inds[j]],$
                           lambda=cwv[inds[j]],asec=asec,isig=outval,$
                           /dointerp,doouter = doouter
         1: radial_profile,copsf[*,*,inds[j]],cens[*,*,inds[j]],$
                           lambda=cwv[inds[j]],asec=asec,imed=outval,$
                           /dointerp,doouter = doouter
         2: radial_profile,copsf[*,*,inds[j]],(*self.satspots.cens)[*,*,inds[j]],$
                           lambda=cwv[inds[j]],asec=asec,imn=outval,$
                           /dointerp,doouter = doouter
      endcase
      outval *= sclunit
      *contrprof[j] = outval
      if contr_xunit eq 1 then $
         asec *= 1d/3600d*!dpi/180d*gpi_get_constant('primary_diam',default=7.7701d0)/(cwv[inds[j]]*1d-6)
      *asecs[j] = asec

      xrange[0] = xrange[0] < min(asec,/nan)
      xrange[1] = xrange[1] > max(asec,/nan)
      yrange[0] = yrange[0] < min(outval,/nan)
      yrange[1] = yrange[1] > max(outval,/nan)
   endfor

   ;;plot
   if (wind ne -1) || (pngsave ne '') then begin
      if yscale eq 1 then yrange = [contr_yaxis_min, contr_yaxis_max]
      ytitle = 'Contrast '
      case contr_yunit of
         0: ytitle +=  '['+strc(uint(contrsigma))+' sigma limit]'
         1: ytitle += '[Median]'
         2: ytitle += '[Mean]'
      endcase
      xtitle =  'Angular separation '
      if contr_xunit eq 0 then xtitle += '[Arcsec]' else $
         xtitle += '['+'!4' + string("153B) + '!X/D]' ;;"just here to keep emacs from flipping out

      if slice ne -1 then color = cgcolor('red') else begin
         color = round(findgen((size(cube,/dim))[2])/$
                       ((size(cube,/dim))[2]-1)*100.+100.)
      endelse

      if wind ne -1 then begin
		  ; reuse existing window if possible
		  select_window,wind,xsize=800,ysize=600,retain=2 
	  endif else begin
         odevice = !D.NAME
         set_plot,'Z',/copy
         device,set_resolution=[800,600],z_buffer = 0
         erase
      endelse
      plot,[0],[0],ylog=contr_yaxis_type,xrange=xrange,yrange=yrange,/xstyle,/ystyle,$
        xtitle=xtitle,ytitle=ytitle,/nodata, charsize=1.2,background=cgcolor('white'),color = cgcolor('black')
      
      for j = 0, n_elements(inds)-1 do begin
         oplot,*asecs[j],(*contrprof[j])[*,0],color=color[j],linestyle=0
         if doouter then oplot,*asecs[j],(*contrprof[j])[*,1], color=color[j],linestyle=2
      endfor
      
      if pngsave ne '' then begin
         ;;if user set AUTO then synthesize entire path
         if strcmp(strupcase(pngsave),'AUTO') then begin 
            s_OutputDir = Modules[thisModuleIndex].OutputDir
            s_OutputDir = gpi_expand_path(s_OutputDir) 
            if strc(s_OutputDir) eq "" then return, error('FAILURE: supplied output directory is a blank string.')
            
            if ~file_test(s_OutputDir,/directory, /write) then begin
               if gpi_get_setting('prompt_user_for_outputdir_creation',/bool, default=1) then $
                  res =  dialog_message('The requested output directory '+s_OutputDir+' does not exist. Should it be created now?', $
                                        title="Nonexistent Output Directory", /question) else res='Yes'
               
               if res eq 'Yes' then  file_mkdir, s_OutputDir
               
               if ~file_test(s_OutputDir,/directory, /write) then $
                  return, error("FAILURE: Directory "+s_OutputDir+" does not exist or is not writeable.",/alert)
            endif         
            pngsave = s_OutputDir
         endif 
         
         ;;if this is a directory, then you want to save to it with the
         ;;default naming convention
         if file_test(pngsave,/dir) then begin
            nm = DataSet.filenames[numfile]
            strps = strpos(nm,'/',/reverse_search)
            strpe = strpos(nm,'.fits',/reverse_search)
            nm = strmid(nm,strps+1,strpe-strps-1)
            nm = gpi_expand_path(pngsave+'/'+nm+'-contrast_profile.png')
         endif else nm = pngsave

         if wind eq -1 then begin
            snapshot = tvrd()
            tvlct,r,g,b,/get
            write_png,nm,snapshot,r,g,b
            device,z_buffer = 1
            set_plot,odevice
         endif else write_png,nm,tvrd(true=1)
      endif
   endif

   ;;save radial contrast as fits
   if radialsave ne '' then begin
      ;;if user set AUTO then synthesize entire path
      if strcmp(strupcase(radialsave),'AUTO') then begin 
         s_OutputDir = Modules[thisModuleIndex].OutputDir
         s_OutputDir = gpi_expand_path(s_OutputDir) 
         if strc(s_OutputDir) eq "" then return, error('FAILURE: supplied output directory is a blank string.')
         
         if ~file_test(s_OutputDir,/directory, /write) then begin
            if gpi_get_setting('prompt_user_for_outputdir_creation',/bool, default=1) then $
               res =  dialog_message('The requested output directory '+s_OutputDir+' does not exist. Should it be created now?', $
                                     title="Nonexistent Output Directory", /question) else res='Yes'
            
            if res eq 'Yes' then  file_mkdir, s_OutputDir
            
            if ~file_test(s_OutputDir,/directory, /write) then $
               return, error("FAILURE: Directory "+s_OutputDir+" does not exist or is not writeable.",/alert)
         endif         
         radialsave = s_OutputDir
      endif 
      
      ;;if this is a directory, then you want to save to it with the
      ;;default naming convention
      if file_test(radialsave,/dir) then begin
         nm = DataSet.filenames[numfile]
         strps = strpos(nm,'/',/reverse_search)
         strpe = strpos(nm,'.fits',/reverse_search)
         nm = strmid(nm,strps+1,strpe-strps-1)
         nm = gpi_expand_path(radialsave+path_sep()+nm+'-contrast_profile.fits')
      endif else nm = radialsave
      
      out = dblarr(n_elements(*asecs[inds[0]]), n_elements(inds)+1)+!values.d_nan
      out[*,0] = *asecs[inds[0]]
      for j=0,n_elements(inds)-1 do $
         out[where((*asecs[inds[0]]) eq (*asecs[inds[j]])[0]):n_elements(*asecs[inds[0]])-1,j+1] = $
         (*contrprof[inds[j]])[*,0]

      tmp = intarr((size(cube,/dim))[2])
      tmp[inds] = 1
      slices = string(strtrim(tmp,2),format='('+strtrim(n_elements(tmp),2)+'(A))')
      
      mkhdr,hdr,out
      sxaddpar,hdr,'SLICES',slices,'Cube slices used.'
      sxaddpar,hdr,'YUNITS',(['Std Dev','Median','Mean'])[contr_yunit],'Contrast units'

      writefits,nm,out,hdr
   endif 
   
endif

@__end_primitive 


end
