;+
; NAME: control_data_quality
; PIPELINE PRIMITIVE DESCRIPTION: Control quality of data 
;
;	
;	
;
; INPUTS: data-cube
;
;
; KEYWORDS:
;
; GEM/GPI KEYWORDS:AVRGNOT,GPIHEALT,RMSERR
; DRP KEYWORDS:  	 
;
; OUTPUTS:  
;
; PIPELINE COMMENT: Control quality of data using keywords. Appropriate action for bad quality data is user-defined. 
; PIPELINE ARGUMENT: Name="Action" Type="int" Range="[0,10]" Default="1" Desc="0:Simple alert and continue reduction, 1:Reduction fails"
; PIPELINE ARGUMENT: Name="r0" Type="float" Range="[0,2]" Default="0.08" Desc="critical r0 [m] at lambda=0.5microms"
; PIPELINE ARGUMENT: Name="rmserr" Type="float" Range="[0,1000]" Default="10." Desc="Critical rms wavefront error in microms. "
; PIPELINE ORDER: 1.5
; PIPELINE TYPE: ALL-SPEC
; PIPELINE SEQUENCE: 
;
; HISTORY:
;   JM 2010-10 : created
;
;- 

function control_data_quality, DataSet, Modules, Backbone

primitive_version= '$Id: control_data_quality.pro 96 2010-10-30 13:47:13Z maire $' ; get version from subversion to store in header history
 
@__start_primitive

  if tag_exist( Modules[thisModuleIndex], "r0") then criticalr0=float(Modules[thisModuleIndex].r0) else criticalr0=0.08
  if tag_exist( Modules[thisModuleIndex], "rmserr") then criticalrmserr=float(Modules[thisModuleIndex].rmserr) else criticalrmserr=10.

    badquality=0
    drpmessage='ALERT '
    if numext eq 0 then hdr= *(dataset.headers)[numfile] else hdr=*(dataset.headersPHU)[numfile]
  	;hdr= *(dataset.headers)[0]
  	;;control GPI health
  	health=strcompress(SXPAR( hdr, 'GPIHEALT',count=cc), /rem)
  	if strmatch(health,'WARNING',/fold) || strmatch(health,'BAD',/fold) then begin
  	    badquality=1
  	    drpmessage+='GPI-health='+health
  	endif
  	;;RAWGEMQA keyword tested?
  	
  	;;control r0
  	r0=strcompress(SXPAR( hdr, 'AVRGNOT',count=cc), /rem) ;r0 [m] at 500nm
  	if cc eq 0 then r0=strcompress(SXPAR( hdr, 'R0_TOT',count=cc), /rem)
  	 if  (float(r0) lt criticalr0) then begin
  	    badquality=1
        drpmessage+=' r0[m]='+r0  	 
  	 endif
  	 
  	 ;;control rms error
  	rmserr=strcompress(SXPAR( hdr, 'RMSERR',count=cc), /rem) 
  	    if  (float(rmserr) gt criticalrmserr) then begin
        badquality=1
        drpmessage+=' rms waveront error [microms]='+rmserr     
     endif

if badquality  then begin
  action=uint(Modules[thisModuleIndex].Action)
  case action of
    0:begin
        print, 'BAD QUALITY DATA: '+drpmessage
         backbone->Log, strjoin(drpmessage), /DRF, DEPTH = 1
         backbone->Log, strjoin(drpmessage), /GENERAL, DEPTH = 1
       sxaddparlarge,*(dataset.headers[numfile]),'HISTORY',functionname+"ALERT BAD QUALITY DATA"+drpmessage
      end
    1: begin
      return, error('REDUCTION FAILED ('+strtrim(functionName)+'):'+drpmessage)
    end
  
  endcase
endif


  return, ok

end
