;+
; NAME: testphotometry001
; PIPELINE PRIMITIVE DESCRIPTION: Test the photometric calibration 
;
; INPUTS: 
;
;
; KEYWORDS:
; 
;
; OUTPUTS:  
;
; PIPELINE COMMENT: Test the photometry calibration by comparing extracted companion spectrum with DST initial spectrum.
; PIPELINE ARGUMENT: Name="suffix" Type="string"  Default="-photom" Desc="Enter suffix of figures names"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="0" Desc="1-500: choose gpitv session for displaying wavcal file, 0: no display "
; PIPELINE ORDER: 2.52
; PIPELINE TYPE: ALL-SPEC 
; PIPELINE SEQUENCE: 
;
; HISTORY:
;   Jerome Maire 2010-08-16
;- 

function testphotometry001, DataSet, Modules, Backbone
primitive_version= '$Id: testphotometry001.pro 11 2010-08-16 10:22:03 maire $' ; get version from subversion to store in header history
@__start_primitive



;;get last  measured companion spectrum
compspecname=DataSet.OutputFilenames[numfile]
compspecnamewoext=strmid(compspecname,0,strlen(compspecname)-5)
res=file_search(compspecnamewoext+'*spec*fits')
extr=readfits(res[0],hdrextr)
lambdaspec=extr[*,0]
;espe=extr[*,2]
COMPMAG=float(sxpar(hdrextr,'COMPMAG'))
COMPSPEC=sxpar(hdrextr,'COMPSPEC') ;we could have compsep&comprot

;;get DST companion spectrum
;restore, 'E:\GPI\dst\'+strcompress(compspec,/rem)+'compspectrum.sav'
case strcompress(filter,/REMOVE_ALL) of
  'Y':specresolution=30.
  'J':specresolution=38.
  'H':specresolution=45.
  'K1':specresolution=55.
  'K2':specresolution=60.
endcase

        ;get the common wavelength vector
            ;error handle if extractcube not used before
         cwv=get_cwv(filter)
        CommonWavVect=cwv.CommonWavVect
        lambda=cwv.lambda
        lambdamin=CommonWavVect[0]
        lambdamax=CommonWavVect[1]

dlam=((lambdamin+lambdamax)/2.)/specresolution
nlam=(lambdamax-lambdamin)/dlam
lambdalow= lambdamin+(lambdamax-lambdamin)*(findgen(floor(nlam))/floor(nlam))+0.5*(lambdamax-lambdamin)/floor(nlam)
print, 'delta_lambda [um]=', dlam, 'spectral resolution=',specresolution,'#canauxspectraux=',nlam,'vect lam=',lambdalow

repDST=getenv('GPI_IFS_DIR')+path_sep()+'dst'+path_sep()
case strcompress(compspec,/rem) of
'L1': begin
fileSpectra=repDST+'compspec'+path_sep()+'L1_2MASS0345+25.txt'
refmag=13.169 ;Stephens et al 2003
end
'L5':begin
fileSpectra=repDST+'compspec'+path_sep()+'L5_SDSS2249+00.txt'
refmag=15.366 ;Stephens et al 2003
end
'L8':begin
fileSpectra=repDST+'compspec'+path_sep()+'L8_SDSS0857+57.txt'
refmag=13.855 ;Stephens et al 2003
end
'M9V':begin
fileSpectra=repDST+'compspec'+path_sep()+'M9V_LP944-20.txt'
refmag=10.017 ;Cushing et al 2004
end
'T3':begin
fileSpectra=repDST+'compspec'+path_sep()+'T3_SDSS1415+57.txt'
refmag=16.09 ;Chiu et al 2006
end
'T7':begin
fileSpectra=repDST+'compspec'+path_sep()+'T7_Gl229B.txt'
refmag=14.35 ;Leggett et al 1999
end
'T8':begin
fileSpectra=repDST+'compspec'+path_sep()+'T8_2MASS0415-09.txt'
refmag=15.7 ; Knapp et al. 2004 AJ
end
'Flat':begin
fileSpectra=repDST+'compspec'+path_sep()+'Flat.txt'
refmag=15.7 ; arbitrary
end
endcase
readcol, fileSpectra[0], lamb, spec,/silent  

  LowResolutionSpec=fltarr(n_elements(lambda))
  widthL=(lambda[1]-lambda[0])
  for i=0,n_elements(lambda)-1 do begin
    dummy = VALUE_LOCATE(Lamb, [lambda(i)-widthL/2.])
    dummy2 = VALUE_LOCATE(Lamb, [lambda(i)+widthL/2.])
    if dummy eq dummy2 then LowResolutionSpec[i] = Spec(dummy) else $
    LowResolutionSpec[i] = (1./((Lamb(dummy+1)-Lamb(dummy))*(dummy2-dummy)))*INT_TABULATED(Lamb(dummy:dummy2),Spec(dummy:dummy2),/DOUBLE)
  endfor


;smooth to the resolution of the spectrograph:
verylowspec=changeres(LowResolutionSpec, lambda,lambdalow)
;then resample on the common wavelength vector:
verylowspec2=changeres(verylowspec, lambdalow,lambda)
theospectrum=(10.^(-(compmag-refmag)/2.5))*verylowspec2
print, 'theo comp. spec=',theospectrum
ewav=extr[*,0]
espe=extr[*,2] ;indice 2 selects the standard photometric measurement (DAOphot-like)


truitime=float(sxpar(header,'TRUITIME'))
starmag=double(SXPAR( header, 'Hmag'))
;;;PLOT RESULTS
;;prepare the plot
maxvalue=max([(10.^(-(compmag-refmag)/2.5))*verylowspec2,espe])
expo=floor(abs(alog10(maxvalue))+1.)
factorexpo=10.^expo 
thisLetter = "155B
greekLetter = '!9' + String(thisLetter) + '!X'
print, greekLetter
units=' W/m^2/'+greekLetter+'m'

basen=file_basename(res[0])
basenwoext=strmid(basen,0,strlen(basen)-5)
openps,getenv('GPI_DRP_OUTPUT_DIR')+path_sep()+'fig'+path_sep()+basenwoext+'.ps', xsize=17, ysize=27 ;, ysize=10, xsize=15
  !P.MULTI = [0, 1, 3, 0, 0] 
units=TeXtoIDL(" W/m^{2}/\mum")
deltaH=TeXtoIDL(" \Delta H=")
print, 'units=',units
expostr = TeXtoIDL(" 10^{-"+strc(expo)+"}")
plot, ewav, factorexpo*espe,ytitle='Flux density ['+expostr+units+']', xtitle='Wavelength (' + greekLetter + 'm)',$
 xrange=[ewav[0],ewav[n_elements(ewav)-1]],yrange=[0,10.],psym=1, charsize=1.5 
;oplot, lambda,(2.55^(3.09))*30.*lowresolutionspec,linestyle=1
oplot, lambda,factorexpo*theospectrum,linestyle=0
legend,['measured spectrum','input '+strcompress(compspec,/rem)+' spectrum, H='+strc(compmag)+deltaH+strc(compmag-starmag)],psym=[1,-0]

plot,ewav,(espe-theospectrum),ytitle='Difference of Flux density ['+units+'] (meas.-theo.)', xtitle='Wavelength (' + greekLetter + 'm)', $
xrange=[ewav[0],ewav[n_elements(ewav)-1]],psym=-1, charsize=1.5 
plot,ewav, 100.*abs(espe-theospectrum)/theospectrum,ytitle='Abs. relative Diff. of Flux density [%] (abs(meas.-theo.)/theo)', xtitle='Wavelength (' + greekLetter + 'm)',$
 xrange=[ewav[0],ewav[n_elements(ewav)-1]],yrange=[0,100.],psym=-1, charsize=1.5 
xyouts, ewav[2],70.,'mean error='+strc(mean(100.*abs(espe-theospectrum)/theospectrum), format='(f5.2)')+' %'
closeps
set_plot,'win'

return, ok
 end