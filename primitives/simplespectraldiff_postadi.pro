;+
; NAME: SSSimpleDiff
; PIPELINE PRIMITIVE DESCRIPTION: Simple SSDI of median ADI residual
;
; 		This recipe rescales and subtracts 2 frames in different user-defined bandwidths. This recipe is used for speckle suppression using the Marois et al (2000) algorithm.
;
;		This routine does NOT update the data structures in memory. You **MUST**
;		set the keyword SAVE=1 or else the output is silently discarded.
;
; INPUTS: 
; 	input datacube 
; 	wavelength solution from common block
;
; KEYWORDS:
; 	L1Min=		Wavelength range 1, minimum wavelength [in microns]
; 	L1Max=		Wavelength range 1, maximum wavelength [in microns]
; 	L2Min=		Wavelength range 2, minimum wavelength [in microns]
; 	L2Max=		Wavelength range 2, maximum wavelength [in microns]
; 	k=			Multiplicative coefficient for multiplying the image for
; 				Wavelength Range *2*. Default value is k=1. 
;
; 	/Save		Set to 1 to save the output file to disk
;
; OUTPUTS:
;
; ALGORITHM:
;	Given the user's specified wavelength ranges, extract the 3D datacube slices
;	for each of those wavelength ranges. Collapse these down into 2D images by
;	simply averaging the values at each lenslet (ignoring NANs).  Rescale Image1
;	using fftscale so that the PSF scale matches that of Image2 (as computed
;	from the average wavelength for each image). Then compute
;	   diffImage = I1scaled - k* I2
;	Then hopefully output the image somewhere if SAVE=1 is set. 
;
; PIPELINE COMMENT: Apply SSDI to create a 2D subtracted image from a cube. Given the user's specified wavelength ranges, extract the 3D datacube slices for each of those wavelength ranges. Collapse these down into 2D images by simply averaging the values at each lenslet (ignoring NANs).  Rescale Image1, then compute  diffImage = I1scaled - k* I2
; PIPELINE ARGUMENT: Name="L1Min" Type="float" Range="[0.9,2.5]" Default="1.55" Desc="Wavelength range 1, minimum wavelength [in microns]"
; PIPELINE ARGUMENT: Name="L1Max" Type="float" Range="[0.9,2.5]" Default="1.57" Desc="Wavelength range 1, maximum wavelength [in microns]"
; PIPELINE ARGUMENT: Name="L2Min" Type="float" Range="[0.9,2.5]" Default="1.60" Desc="Wavelength range 2, minimum wavelength [in microns]"
; PIPELINE ARGUMENT: Name="L2Max" Type="float" Range="[0.9,2.5]" Default="1.65" Desc="Wavelength range 2, maximum wavelength [in microns]"
; PIPELINE ARGUMENT: Name="k" Type="float" Range="[0,10]" Default="1.0" Desc="Scaling factor of Intensity(wav_range2) with diffImage = I1scaled - k* I2"
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="1" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="5" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 4.3
; PIPELINE TYPE: ASTR/SPEC HIDDEN
; PIPELINE SEQUENCE: 2-3-
;
;
; HISTORY:
; 	2007-11 Jerome Maire
;	2009-04-15 MDP: Documentation updated; slight code cleanup 
;    2009-09-17 JM: added DRF parameters
;-

Function  simpleSpectraldiff_postadi, DataSet, Modules, Backbone
common PIP
COMMON APP_CONSTANTS


  getmyname, functionname

 
cubefin=*(dataset.currframe[0])
;thisModuleIndex = drpModuleIndexFromCallSequence(Modules, functionName)
thisModuleIndex = Backbone->GetCurrentModuleIndex()
L1min=Modules[thisModuleIndex].L1min
L1max=Modules[thisModuleIndex].L1max
L2min=Modules[thisModuleIndex].L2min
L2max=Modules[thisModuleIndex].L2max
k=Modules[thisModuleIndex].k
if ~(keyword_set(k)) then k=1.

;        cwv=get_cwv('H')
;        CommonWavVect=cwv.CommonWavVect
lambdamin=CommonWavVect(0)
lambdamax=CommonWavVect(1)
;Common Wavelength Vector
lambda=dblarr(CommonWavVect(2))
for i=0,CommonWavVect(2)-1 do lambda(i)=lambdamin+double(i)*(lambdamax-lambdamin)/(CommonWavVect(2)-1)

;print, lambda

numL1=VALUE_LOCATE(lambda,double(L1min) )
numL2=VALUE_LOCATE(lambda,double(L1max) )
numL3=VALUE_LOCATE(lambda,double(L2min) )
numL4=VALUE_LOCATE(lambda,double(L2max) )
;print, 'SSSimplediff tranches:',numL1,numL2,numL3,numL4
L1=lambda[numL1]
L2=lambda[numL2]
L3=lambda[numL3]
L4=lambda[numL4]
; compute the middle/average wavelength for each chosen slice
L1m=double(L1)+0.5*(double(L2)-double(L1))
L2m=double(L3)+0.5*(double(L4)-double(L3))
; extract the slices from the datacube and collapse them to 2D images
;note that following 2 code lines remove a lot of nan...
I1=avg(Cubefin[*,*,numL1:numL2],2,/double,/nan)
I2=avg(Cubefin[*,*,numL3:numL4],2,/double,/nan)

wnf1 = where(~FINITE(I1),nancount1)
wnf2 = where(~FINITE(I2),nancount2)
if nancount1 gt 0 then I1[wnf1]=0.
if nancount2 gt 0 then I2[wnf2]=!VALUES.F_NAN
	; QUERY BY MDP: Why are I1 and I2 not handled the same way here??
	;ANS JM: 0 for I1 corners because  the fftscale do not work with Nan. 


;;fftscale bugs with image of odd size:
szim=size(I1)
if (szim[1] mod 2) then begin
  I1=I1[0:szim[1]-2,0:szim[2]-2]
  I2=I2[0:szim[1]-2,0:szim[2]-2]
endif 


;;todo: handle PSF center before fftscale 
I1s=fftscale(I1,double(L2m)/double(L1m),double(L2m)/double(L1m),1e-7)


;sssd=I2-k*I1s
sssd=I1s-k*I2

;suffix=suffix+'-sssd'
;filenm=strmid(filename,0,strlen(filename)-5)+suffix+'-sssd'+'.fits.gz'
;writefits, filenm ,sssd,header,/compress
thisModuleIndex = Backbone->GetCurrentModuleIndex()

    if tag_exist( Modules[thisModuleIndex], "Save") && ( Modules[thisModuleIndex].Save eq 1 ) then begin
      if tag_exist( Modules[thisModuleIndex], "gpitv") then display=fix(Modules[thisModuleIndex].gpitv) else display=0 
      b_Stat = save_currdata( DataSet,  Modules[thisModuleIndex].OutputDir, suffix+'-sssd', savedata=sssd, display=display)
      if ( b_Stat ne OK ) then  return, error ('FAILURE ('+functionName+'): Failed to save dataset.')
    endif else begin
      if tag_exist( Modules[thisModuleIndex], "gpitv") && ( fix(Modules[thisModuleIndex].gpitv) ne 0 ) then $
          gpitvms, double(*DataSet.currFrame), ses=fix(Modules[thisModuleIndex].gpitv)
    endelse

    

return, ok
end
