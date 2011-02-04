;+
; NAME: GPIProgressBar
;
; 	An object-oriented upgrade for the GPI pipeline
;
; 	This displays a progress window, various status updates, and more.
;
; INPUTS:
; KEYWORDS:
; OUTPUTS:
;
; HISTORY:
;          2009 created by Jerome Maire
; 	       2010-01-19 19:48:56 oriented object - Marshall Perrin 
;-

; Function to check if user pressed the quit button?
function gpiprogressbar::checkquit
 
	return, self.quit
end
pro gpiprogressbar::quit
widget_control,self.base_wid,/destroy
end
function gpiprogressbar::checkabort
	return, self.abort
end
function gpiprogressbar::flushqueue
   return, self.flushq
end
function gpiprogressbar::rescandb
   return, self.rescan
end
pro gpiprogressbar::flushqueue_end
   self.flushq=0
end
pro gpiprogressbar::rescandb_end
   self.rescan=0
end

PRO gpiprogressbar::update
  	WIDGET_CONTROL, (*self.State).wDrawProgress, get_VALUE=drawbar
    wset, drawbar

    wDrawProgress = (*self.State).wDrawProgress
    vProgress = (*self.State).vProgress
    (*self.State).xpos = 300*(vProgress/100.0)

    ERASE, 255
    POLYFILL, [0,0,5+(*pState).xpos,5+(*pState).xpos], $
       [0, 19, 19,0], /device, color=80


end

PRO gpiprogressbar::checkevents
; this routine is used to MANUALLY process events
; to avoid having to use the whole XMANAGER etc code,
; that doesn't play well with a main() loop in the backbone code 
; that runs forever 

res = widget_event(self.base_wid,/nowait)


end


; Event handling dispatch wrapper:
PRO gpiprogressbar_event,ev
  widget_control, ev.top, get_uvalue=wids
  if obj_valid( (*wids).self) then (*wids).self->Event,ev else print, "err?"

end

;Actual event handling:
pro gpiprogressbar::event,ev
      widget_control, ev.id,GET_UVALUE=uval
      if size(uval,/TYPE) eq 7 then begin
      if uval eq 'rescanDB' then self.rescan =1
      if uval eq 'flushqueue' then self.flushq =1
         if uval eq 'quit' then begin
			 conf = dialog_message("Are you sure you want to exit the GPI Data Reduction Pipeline?",/question,title="Confirm Close",/default_no,/center)
			 if conf eq "Yes" then begin
				 ;message,/info, 'Setting pipeline QUIT flag'
				 self.quit =1 ;widget_control, ev.top,/DESTROY
				 ; TODO actually close the entire GPI pipeline now...
				 ;  Actually closing the pipeline requires the main loop to call
				 ;  checkquit()
			 endif
             return
         endif
         if uval eq 'abort' then begin
			 conf = dialog_message("Are you sure you want to abort the current DRF?",/question,title="Confirm abort",/default_no,/center)
			 if conf eq "Yes" then begin
				 ;message,/info, 'Setting pipeline QUIT flag'
				 self.abort =1 ;widget_control, ev.top,/DESTROY
				 ; TODO actually close the entire GPI pipeline now...
				 ;  Actually closing the pipeline requires the main loop to call
				 ;  checkquit()
			 endif
             return
         endif

      endif else begin
         if tag_names(ev,/STRUCTURE_NAME) eq 'WIDGET_BASE' then begin ; resize
			 ;print, "new size: ", ev.x, ev.y
			 ; keep the minimum X size enforced, and split the Y resize up
			 ; between the two list widgets
			 ;
			 ; TODO FIXME
			 ;   Really this should calculate for each widget the exact X pixel
			 ;   spacing neede to fit that window within the 
			 diff = (*uval).diff
            ;WIDGET_CONTROL, (*uval).quit,      SCR_XSIZE = (ev.x > diff[0] )
            widget_control, (*uval).wEventLog,  SCR_XSIZE = (ev.x - diff[0] )>diff[2], SCR_YSIZE=(ev.Y-diff[1])/2
            widget_control, (*uval).wDRFLog,    SCR_XSIZE = (ev.x - diff[0] )>diff[2], SCR_YSIZE=(ev.Y-diff[1])/2
         endif
      endelse
end 
    


;--------------------------------------------
pro gpiprogressbar::set, wid, header, action
	; generic helper routine.
	widget_control, wid, set_value = header+string(action)
end
pro gpiprogressbar::set_status, action
	self->set, (*self.state).wLabelAction, 'Status:  ', action
end
pro gpiprogressbar::set_DRF, DRF
	
	if size(DRF,/TNAME) eq "STRUCT" then begin
		; we were passed a STRUCTQUEUEENTRY probably.
		self->set, (*self.state).wLabelDRF,  '  Latest DRF:          ', DRF.name
	endif else self->set, (*self.state).wLabelDRF,  '  Latest DRF:          ', DRF

	; reset the self.abort flag (in case it was set for the previous DRF) 
	; - we've started a new DRF so might want to abort again?
	self.abort=0

end
pro gpiprogressbar::set_FITS, FITS, number=number, nbtot=nbtot
	; save these for use elsewhere?
	if keyword_set(number) then (*self.state).fits_current_index=number
	if keyword_set(nbtot) then  (*self.state).fits_count=nbtot

	if keyword_set(number) and keyword_set(nbtot) then  extra=strc(number+1)+"/"+strc(nbtot)+", " else extra=""
	self->set, (*self.state).wLabelFITS, '  Latest Input FITS:   ', extra+FITS
end
pro gpiprogressbar::set_action, suffix
	self->set, (*self.state).wLabel2,    '  Current action:      ', suffix
end

pro gpiprogressbar::set_suffix, suffix
	self->set, (*self.state).wLabel2Suf, '  Latest saved suffix: ', suffix
end

pro gpiprogressbar::set_GenLogF, suffix
	self->set, (*self.state).wGenLogF, 'Pipeline Logfile:      ', suffix
end
pro gpiprogressbar::set_DRFLogF, suffix
	self->set, (*self.state).wDRFLogF,    'Latest DRF Logfile:    ', suffix
end
pro gpiprogressbar::set_CalibDir, path
	self->set, (*self.state).id_calibdir, 'Cal Files DB dir:      ',path
end


;---------------------------

pro gpiprogressbar::set_percent, percent_total, percent_currfile
	; Set the status bar percentages. 
	;
	; ARGUMENTS:
	;   percent_total		estimated overall completion % for current DRF.  0-100
	;   percent_currfile	estimated overall completion % for current file. 0-100
	;
	;
	
	; save values
	(*self.State).vProgress = percent_total
	(*self.State).vProgressf = percent_currfile

	; adjust display windows.
	userwin = !D.window
	bars = [(*self.State).wDrawProgress, (*self.State).wDrawProgressf]
	percents = [percent_total, percent_currfile]

	for i=0L,n_elements(bars)-1 do begin
		WIDGET_CONTROL, bars[i], get_VALUE=drawbar
		wset, drawbar	
		Xwidth = (widget_info(bars[i],/geom)).scr_xsize

		; FIXME make this auto-adjust to size...
		xpos = Xwidth*(percents[i]/100.0)
		erase, 255
		POLYFILL, 	[0,0,1+xpos,1+xpos], $
		   			[0, 19, 19,0], /device, color=80
	endfor 


	wset,userwin
end

;---------------------------
pro gpiprogressbar::update, Modules,indexModules, nbtotfile, filenum, status, adi=adi

	; drop-in replacement for update_progressbar module
	self->set_percent, 100.*double(filenum)/double(nbtotfile), 100.*double(indexModules)/double(N_ELEMENTS(Modules)-1)	
	self->set_action, Modules[indexModules<(n_elements(modules)-1)].name
	self->set_Status,  status
	;stop

end



;
;--------------------------------------------
; Append a log string to the event log.
pro gpiprogressbar::log, logstring

	widget_control, (*self.state).wEventLog, get_value=logval
	
	newlog = [logval, logstring]
	if n_elements(newlog) eq self.MAXLOG then newlog = newlog[100:*] ; drop stuff off the top in chunks of 100...

	widget_control, (*self.state).wEventLog, set_value=newlog
	widget_control, (*self.state).wEventLog, set_text_top_line = ((n_elements(newlog)-5)>0)

end

;--------------------------------------------
; Append or replace a log string to the DRF log.
pro gpiprogressbar::DRFlog, logstring, replace=replace

	widget_control, (*self.state).wDRFLog, get_value=logval
	
	if keyword_set(replace) then begin
		newlog = logval
		newlog[n_elements(newlog)-1] = logstring
	endif else begin
		newlog = [logval, logstring]
		if n_elements(newlog) eq self.MAXLOG then newlog = newlog[100:*] ; drop stuff off the top in chunks of 100...
	endelse

	widget_control, (*self.state).wDRFLog, set_value=newlog
	widget_control, (*self.state).wDRFLog, set_text_top_line = ((n_elements(newlog)-5)>0)

end


;--------------------------------------------

function gpiprogressbar::init

    ; Create a common block to hold the widget ID, wChildBase. This
    ; is used to cleanup if processing is completed, the user aborts
    ; or execution ends due to an error.
    COMMON shareWidID, wChildBase
	DEBUG_FRAMES=1

	;self.maxlog = n_elements(self.eventlog)
	self.maxlog=1000

    ; Make simple widget interface.
	wChildBase = WIDGET_BASE(TITLE='GPI Data Pipeline Status Console', /COLUMN, XOFFSET=680 , /TLB_SIZE_EVENTS, /tlb_kill_request_events , resource_name='GPI_DRP')
	self.base_wid = wChildbase
	wChildBase = WIDGET_BASE(self.base_wid, /COLUMN, resource_name='Status')

	;---- overall config 
	w_config_base = widget_base(wChildBase,/column, frame=DEBUG_FRAMES, space=0)
	lab         = widget_label(w_config_base, value="Queue Dir:     "+ getenv('GPI_QUEUE_DIR') ,  xsize=600,/align_left)
	id_calibdir = widget_label(w_config_base, value="Calib Dir:     --"  ,  xsize=600,/align_left)

	wGenLogF = widget_label(w_config_base, value="Pipeline Logfile:      --" ,/align_left, xsize=600)
	wDRFLogF = widget_label(w_config_base, value="Latest DRF Logfile:    --" , /align_left, xsize=600)




	;---- current status
	w_status_base =  widget_base(wChildBase,/column, frame=DEBUG_FRAMES)
	wLabelAction = WIDGET_LABEL(w_status_base, VALUE="" ,  UVALUE='LABEL',/DYNAMIC_RESIZE,/ALIGN_LEFT)
	wLabelDRF = WIDGET_LABEL(w_status_base, VALUE='  ',  UVALUE='LABEL',/DYNAMIC_RESIZE,/ALIGN_LEFT)
	wLabelFITS = WIDGET_LABEL(w_status_base, VALUE='  Lastest Input FITS:  --',  UVALUE='LABEL',/DYNAMIC_RESIZE,/ALIGN_LEFT)
	wLabel2 = WIDGET_LABEL(w_status_base, VALUE='  Action:', UVALUE='LABELP',XSIZE=600,/ALIGN_LEFT)
	wLabel2suf = WIDGET_LABEL(w_status_base, VALUE='  Saved (suffix):',  UVALUE='LABELPsuf',XSIZE=600,/ALIGN_LEFT)

	; status for ENTIRE DRF
	wLabelstatus = WIDGET_LABEL(w_status_base, VALUE=' DRF Completion Status:',  UVALUE='LABEL3',/DYNAMIC_RESIZE)
	wDrawProgress = WIDGET_DRAW(w_status_base, xsize=600, ysize=20, uvalue="PROGRESS")
	; status for CURRENT FILE
	wLabel4 = WIDGET_LABEL(w_status_base, VALUE=' Current File Completion Status:',  UVALUE='LABEL4')
	wDrawProgressf = WIDGET_DRAW(w_status_base, xsize=600, ysize=20, uvalue="PROGRESSF")

	;---- current status
	w_log_base = widget_base(wChildBase,/column, frame=DEBUG_FRAMES,/base_align_left)
	lab = widget_label(w_log_base, value="Pipeline Log Messages:")
	wEventLog = widget_text(w_log_base, ysize=5, xsize=100, /scroll,scr_xsize=595)
	; history of DRFs
	lab = widget_label(w_log_base, value="Processed DRFs:")
	wDRFLog = widget_text(w_log_base, ysize=5, xsize=100, /scroll,scr_xsize=595)

  q=widget_button(wChildBase,VALUE='Rescan Calibration Database',UVALUE='rescanDB', resource_name='red_button')
  q=widget_button(wChildBase,VALUE='Flush DRF queue',UVALUE='flushqueue', resource_name='red_button')
	;---- quit button
	q=widget_button(wChildBase,VALUE='Abort current DRF',UVALUE='abortDRF', resource_name='red_button')
	q=widget_button(wChildBase,VALUE='Quit GPI DRP',UVALUE='quit', resource_name='red_button')


    ; Set initial color table for draw widget.
    DEVICE, DECOMPOSED=0
    LOADCT, 39

	WIDGET_CONTROL, wChildBase, /REALIZE

	; code for resizeable log text widget
	geom_b = widget_info(wChildBase, /GEOM)
	geom_t = widget_info(wEventLog, /GEOM)
	geom_t2 = widget_info(wDRFLog, /GEOM)
	geom_q = widget_info(q, /GEOM)
	; [padding in x, padding in y, minimum X size]
	diff = [geom_b.SCR_XSIZE-geom_t.SCR_XSIZE, geom_b.SCR_YSIZE-geom_t.SCR_YSIZE-geom_t2.SCR_YSIZE, geom_t.SCR_XSIZE]


	State2 = {self:self, wChildBase:self.base_wid, wDrawProgress:wDrawProgress, $
	    wDrawProgressf:wDrawProgressf,vProgress:0,vProgressf:0, xpos:0,xposf:0, $
	    wLabelAction:wLabelAction, wLabelDRF:wLabelDRF, wLabelFITS:wLabelFITS,wLabel2:wLabel2,wLabel2suf:wLabel2suf,wLabelstatus:wLabelstatus, $
		wEventLog: wEventLog, wDRFLog: wDRFLog, wGenLogF: wGenLogF, wDRFLogF: wDRFLogF, id_calibdir:id_calibdir, diff:diff, fits_count:0L, fits_current_index: 0L, quit: q}
	pState = PTR_NEW(State2)
	WIDGET_CONTROL, self.base_wid, SET_UVALUE=pState
	
    if (not(xregistered('gpiprogressbar', /noshow))) then begin
        xmanager, 'gpiprogressbar', self.base_wid,/NO_BLOCK
    endif


	self.state = pState
	print, "GPI progress bar init ok"


	self->Set_status, 'watching for DRFs but idle'
	self->Set_percent,0.1,0.1
	self->Set_DRF, '--'
	self->Set_FITS, '--'
	self->Set_action, '--'
	self->Set_suffix, '--'
	
	return, 1

end


pro gpiprogressbar__define

MAXLOG = 1000

st = {gpiprogressbar, $
	state: ptr_new(),$
	quit: 0L, $
	abort: 0L, $
	flushq:0L,$
	rescan:0L,$
	;eventlog: strarr(maxlog), $
	;drflog: strarr(maxlog), $
	maxlog: MAXLOG, $
	base_wid: 0L $
}

end
