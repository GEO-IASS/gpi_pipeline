pro plot_sat_vals,lambda,sats,w=w
;+
; NAME:
;       plot_sat_vals
;
; PURPOSE:
;       Plot the intensities of the satellite spots
;
; Calling SEQUENCE:
;       plot_sat_vals,lambda,sats,[w=w]
;
; INPUT/OUTPUT:
;       lambda - Array of wavelengths (dimension L)
;       sats - 4xLxN array of satellite fluxes (N can be 1 for a
;              single cube or >1 for multiple cubes)
;       w - Window number to plot in (defaults to 23)
;
; OPTIONAL OUTPUT:
;       None.
;
; EXAMPLE:
;
;
; DEPENDENCIES:
;	None
;
; NOTES: 
;      
;             
; REVISION HISTORY
;       Written 2012 - ds
;-

if (size(sats))[0] eq 2 then numim = 1 else numim = (size(sats,/dim))[2]
cols = [cgcolor('red'),cgcolor('blue'),cgcolor('dark green'),cgcolor('navy')]

if not(keyword_set(w)) then w = 23
window,w,xsize=800,ysize=600,retain=2 

thisLetter = "154B ;"
greekLetter = '!4' + String(thisLetter) + '!X'

plot,/nodata,[min(lambda),max(lambda)],[min(sats),max(sats)],$
     charsize=1.5, Background=cgcolor('white'), Color=cgcolor('black'),$
     xtitle='Wavelength (' + greekLetter + 'm)',ytitle='Maximum Satellite Flux'
for k=0,numim-1 do for j=0,3 do begin 
   oplot,lambda,sats[j,*,k],color=cols[j]
   oplot,lambda,sats[j,*,k],psym=(k mod 6)+1,color=cols[j]
endfor

end
