pro gpi_rotate_header_satspots,backbone,ang,locs
;+
; NAME:
;      GPI_ROTATE_HEADER_SATSPOTS
;
; PURPOSE:
;      Rotate satspot pixel locations by given angle and write to header
;
; CALLING SEQUENCE:
;      gpi_rotate_header_satspots,backbone,ang,locs
;
; INPUTS:
;      Backbone - Pipeline backbone object
;      ang - Angle to rotate by (degrees)
;      locs - 2x4xl array of sat locations
;      imcent - Rotation pivot point.  If not set, use image center.
;
; OUTPUTS:
;
; COMMON BLOCKS:
;     
;
; RESTRICTIONS:
;
; EXAMPLE:
;
; NOTES:
;     Remember that the coordinate system is left-handed
;
; MODIFICATION HISTORY:
;	Written 11.08.2013 - ds
;-

  compile_opt defint32, strictarr, logical_predicate

  if ~keyword_set(ang) then begin
     backbone->log,'GPI_ROTATE_HEADER_SATSPOTS: No angle given.'
     return
  endif 

  if ~keyword_set(locs) then begin
     backbone->log,'GPI_ROTATE_HEADER_SATSPOTS: No satspot locations given.'
     return
  endif 

  sz = size(locs,/dim)
  if (n_elements(sz) ne 3) || (sz[0] ne 2) || (sz[1] ne 4) then begin
     backbone->log,'GPI_ROTATE_HEADER_SATSPOTS: locs must be 2x4xl array.'
     return
  endif 
  nlam = sz[2]

  if ~keyword_set(imcent) then begin
     imsize = [backbone->get_keyword('NAXIS1',count=ct1),backbone->get_keyword('NAXIS2',count=ct2)]
     if ct1+ct2 ne 2 then begin
        backbone->log,'GPI_ROTATE_HEADER_SATSPOTS: NAXISi keywords not found in header.'
        return
     end 
     imcent = (imsize-1)/2d0
  endif 
  
  newlocs = dblarr(2,4,nlam)
  rotang = ang*!dpi/180d0 ;;deg->rad
  rotMat = [[cos(rotang),sin(rotang)],$
            [-sin(rotang),cos(rotang)]]
  c0 = imcent # (dblarr(4) + 1d0)
  for j = 0,nlam-1 do newlocs[*,*,j] = (rotMat # (locs[*,*,j] - c0))+c0
  
  for s=0,nlam - 1 do begin
     for j = 0,3 do begin
        backbone->set_keyword,'SATS'+strtrim(s,2)+'_'+strtrim(j,2),$
                              string(strtrim(newlocs[*,j,s],2),format='(F7.3," ",F7.3)'),$
                              'Location of sat. spot '+strtrim(j,2)+' of slice '+strtrim(s,2),$
                              ext_num=1
     endfor
  endfor
 
end



