;---------------------------------------------------------------------
;automaticreducer__define.PRO
;
;	Automatic detection and parsing of GPI files. 
;
;	This inherits the Parser GUI, and internally makes use of Parser GUI
;	functionality for parsing the files, but does not display the parser GUI
;	widgets in any form. 
;
; HISTORY:
;
; Jerome Maire - 15.01.2011
; 2012-02-06 MDP: Various updated to path handling
; 			Also updated to use WIDGET_TIMER events for monitoring the directory
; 			so this works properly with the event loop
; 2012-02-06 MDP: Pretty much complete rewrite.
; 2013-03-28 JM: added manual shifts of the wavecal
;---------------------------------------------------------------------





function automaticreducer::refresh_file_list, count=count, init=init, _extra=_extra
	; Do the initial check of the files that are already in that directory. 
	;
	; Determine the files that are there already
	; If there are new files:
	; 	Display the list sorted by file access time
	;
	; KEYWORDS:
	;    count	returns the # of files found

    filetypes = '*.{fts,fits}'
    searchpattern = self.dirinit + path_sep() + filetypes
	current_files =FILE_SEARCH(searchpattern,/FOLD_CASE, count=count)
	
	if count gt 0 and widget_info(self.ignore_raw_reads_id,/button_set) then begin
		mask_real_files = ~strmatch(current_files, '*_[0-9][0-9][0-9].fits')
		wreal = where(mask_real_files, count)
		if count eq 0 then current_files='' else current_files = current_files[wreal]
		
		; FIXME more sophisticated rejection here?
	endif



	dateold=dblarr(n_elements(current_files))
	for j=0L,long(n_elements(current_files)-1) do begin
		Result = FILE_INFO(current_files[j] )
		dateold[j]=Result.ctime
	endfor
	;list3=current_files[REVERSE(sort(dateold))] ; ascending
	list3=current_files[(sort(dateold))]  ; descending

	if keyword_set(init) then begin
		if count gt 0 then $
			self->Log, 'Found '+strc(count) +" files on startup of automatic processing. Skipping those..." $
		else $
			self->Log, 'No FITS files found in that directory yet...' 
		widget_control, self.listfile_id, SET_VALUE= list3 ;[0:(n_elements(list3)-1)<(self.maxnewfile-1)] ;display the list
		widget_control, self.listfile_id, set_uvalue = list3  ; because oh my god IDL is stupid and doesn't provide any way to retrieve
															  ; values from a  list widget!   Argh. See
															  ; http://www.idlcoyote.com/widget_tips/listselection.html 
		widget_control, self.listfile_id, set_list_top = 0>(n_elements(list3) -8) ; update the scroll position in the list
		self.previous_file_list = ptr_new(current_files) ; update list for next invocation
		count=0
		return, ''

	endif

	new_files = cmset_op( current_files, 'AND' ,/NOT2, *self.previous_file_list, count=count)

	if count gt 0 then begin
		widget_control, self.listfile_id, SET_VALUE= list3 ;[0:(n_elements(list3)-1)<(self.maxnewfile-1)] ;display the list
		widget_control, self.listfile_id, set_uvalue = list3  ; because oh my god IDL is stupid and doesn't provide any way to retrieve this later
		widget_control, self.listfile_id, set_list_top = 0>(n_elements(list3) -8) ; update the scroll position in the list
		*self.previous_file_list = current_files ; update list for next invocation
		return, new_files
	endif else begin
		return, ''
	endelse



end

;--------------------------------------------------------------------------------



pro automaticreducer::run
	; This is what runs every 1 second to check the contents of that directory

	if ~ptr_valid( self.previous_file_list) then begin
		ignore_these = self->refresh_file_list(/init) 
		return
	endif

	new_files = self->refresh_file_list(count=count)
	
	if count eq 0 then return  ; no new files found

	message,/info, 'Found '+strc(count)+" new files to process!"
	for i=0,n_elements(new_files)-1 do self->log, "New file: "+new_files[i]

	self->handle_new_files, new_files


;	if chang ne '' then begin
;		  widget_control, self.listfile_id, SET_VALUE= list2[0:(n_elements(list2)-1)<(self.maxnewfile-1)] ;display the list
;		  ;check if the file has been totally copied
;		  self.parserobj=gpiparsergui( chang,  mode=self.parsemode)
;	endif
end

;-------------------------------------------------------------------

pro automaticreducer::handle_new_files, new_filenames ;, nowait=nowait
	; Handle one or more new files that were either
	;   1) detected by the run loop, or
	;   2) manually selected and commanded to be reprocessed by the user.
	;
	
	
	   
	if self.parsemode eq 1 then begin
		; process the file right away
		for i=0L,n_elements(new_filenames)-1 do begin
            if strc(new_filenames[i]) eq  '' then begin
                message,/info, ' Received an empty string as a filename; ignoring it.'
                continue
            endif
            finfo = file_info(new_filenames[i])
            if (finfo.size ne 20998080) and (finfo.size ne 21000960) and (finfo.size ne 16790400) then begin
                message,/info, "File size is not an expected value: "+strc(finfo.size)+" bytes. Waiting 0.5 s for file write to complete?"
                wait, 0.5
            endif

			if widget_info(self.view_in_gpitv_id,/button_set) then if obj_valid(self.launcher_handle) then $
				self.launcher_handle->launch, 'gpitv', filename=new_filenames[i], session=45 ; arbitrary session number picked to be 1 more than this launcher
			self->reduce_one, new_filenames[i];,wait=~(keyword_set(nowait))
		endfor

	endif else begin
		; save the files to process later
		if ptr_valid(self.awaiting_parsing) then *self.awaiting_parsing = [*self.awaiting_parsing, new_filenames] else self.awaiting_parsing = ptr_new(new_filenames)
	endelse

end

;-------------------------------------------------------------------

pro automaticreducer::reduce_one, filenames, wait=wait
	; Reduce one single file at a time

    if strc(filenames[0]) eq '' then begin
        message,/info, ' Received an empty string as a filename; ignoring it.'
        return
    endif

    if keyword_set(wait) then  begin
        message,/info, "Waiting 0.5 s to ensure FITS header gets updated first?"
        wait, 0.5
    endif

	if self.user_template eq '' then begin
		; Determine default template based on file type

		info = gpi_load_fits(filenames[0], /nodata)
		prism = strupcase(gpi_simplify_keyword_value(gpi_get_keyword( *info.pri_header, *info.ext_header, 'DISPERSR', count=dispct) ))

		if (dispct eq 0) or (strc(prism) eq '') then begin
			message,/info, 'Missing or blank DISPERSR keyword!'
			if widget_info(self.b_spectral_id,/button_set) then prism = 'PRISM'
			if widget_info(self.b_undispersed_id,/button_set) then prism='WOLLASTON'
			if widget_info(self.b_polarization_id,/button_set) then prism = 'OPEN'
		endif

		if ((prism ne 'PRISM') and (prism ne 'WOLLASTON') and (prism ne 'OPEN')) then begin
			message,/info, 'Unknown DISPERSR: '+prism+". Must be one of {PRISM, WOLLASTON, OPEN} or their Gemini-style equivalents."
			if widget_info(self.b_spectral_id,/button_set) then prism = 'PRISM'
			if widget_info(self.b_undispersed_id,/button_set) then prism='WOLLASTON'
			if widget_info(self.b_polarization_id,/button_set) then prism = 'OPEN'
			message,/info, 'Applying default setting instead: '+prism
		endif

		case prism of
		'PRISM': templatename='Quicklook Automatic Datacube Extraction'
		'WOLLASTON': templatename='Quicklook Automatic Polarimetry Extraction'
		'OPEN':templatename='Quicklook Automatic Undispersed Extraction'
		endcase
	endif else begin
		templatename = self.user_template
	endelse
		

	
	self->Log, "Using template: "+templatename
	templatefile= self->lookup_template_filename(templatename) ; gpi_get_directory('GPI_DRP_TEMPLATES_DIR')+path_sep()+templatename
	if templatefile eq '' then return ; couldn't find requested template therefore do nothing.

	drf = obj_new('DRF', templatefile, parent=self,/silent)
	drf->set_datafiles, filenames
	drf->set_outputdir,/autodir


	; generate a nice descriptive filename
	first_file_basename = (strsplit(file_basename(filenames[0]),'.',/extract))[0]

	drf->savedrf, 'auto_'+first_file_basename+'_'+drf->get_datestr()+'.waiting.xml',/autodir
	drf->queue

	obj_destroy, drf

end


;-------------------------------------------------------------------
PRO automaticreducer_event, ev
	; simple wrapper to call object routine
    widget_control,ev.top,get_uvalue=storage
   
    if size(storage,/tname) eq 'STRUCT' then storage.self->event, ev else storage->event, ev
end

;-------------------------------------------------------------------
pro automaticreducer::event, ev
	; Event handler for automatic parser GUI


	uname = widget_info(ev.id,/uname)

	case tag_names(ev, /structure_name) of
		'WIDGET_TIMER' : begin
			self->run
			widget_control, ev.top, timer=1 ; check again at 1 Hz
			return
		end

      'WIDGET_TRACKING': begin ; Mouse-over help text display:
        if (ev.ENTER EQ 1) then begin 
              case uname of 
                  'changedir':textinfo='Click to select a different directory to watch for new files.'
				  'one': textinfo='Each new file will be reduced on its own right away.'
				  'keep': textinfo='All new files will be reduced in a batch whenever you command.'
                  'search':textinfo='Start the looping search of new FITS placed in the right-top panel directories. Restart the detection for changing search parameters.'
                  'filelist':textinfo='List of most recent detected FITS files in the watched directory. '
				  'view_in_gpitv': textinfo='Automatically display new files in GPITV.'
				  'ignore_raw_reads': textinfo='Ignore the extra files for the CDS/UTR reads, if present.'
                  'one':textinfo='Parse and process new file in a one-by-one mode.'
                  'new':textinfo='Change parser queue to process when new type detected.'
                  'keep':textinfo='keep all detected files in parser queue.'
                  'flush':textinfo='Delete all files in the parser queue.'
				  'Start': textinfo='Press to start scanning that directory for new files'
				  'Reprocess': textinfo='Select one or more existing files, then press this to re-reduce them.'
				  'View_one': textinfo='Select one existing file, then press this to view in GPItv.'
                  "QUIT":textinfo='Click to close this window.'
              else:textinfo=' '
              endcase
              widget_control,self.information_id,set_value=textinfo
          ;widget_control, event.ID, SET_VALUE='Press to Quit'   
        endif else begin 
              widget_control,self.information_id,set_value=''
          ;widget_control, event.id, set_value='what does this button do?'   
        endelse 
        return
    end
      
	'WIDGET_BUTTON':begin
	   if uname eq 'changedir' then begin
			dir = DIALOG_PICKFILE(PATH=self.dirinit, Title='Choose directory to scan...',/must_exist , /directory)
			if dir ne '' then begin
				self->Log, 'Directory changed to '+dir
				self.dirinit=dir
				widget_control, self.watchdir_id, set_value=dir
				ptr_free, self.previous_file_list ; we have lost info on our previous files so start over
			endif
   
	   endif
 
		if (uname eq 'one') || (uname eq 'new') || (uname eq 'keep') then begin
		  if widget_info(self.parseone_id,/button_set) then self.parsemode=1
		  if widget_info(self.parseall_id,/button_set) then self.parsemode=3
		endif
		if uname eq 'flush' then begin
			self.parserobj=gpiparsergui(/cleanlist)
		endif
		  
		if uname eq 'alwaysexec' then begin
			self.alwaysexecute=widget_info(self.alwaysexecute_id,/button_set)
		endif
		
    if uname eq 'changeshift' then begin
        directory = gpi_get_directory('calibrations_DIR') 
        widget_control, self.shiftx_id, get_value=shiftx
        widget_control, self.shifty_id, get_value=shifty
        writefits, directory+path_sep()+"shifts.fits", [float(shiftx),float(shifty)]
     endif
		
		
		if uname eq 'QUIT'    then begin
			if confirm(group=ev.top,message='Are you sure you want to close the Automatic Reducer Parser GUI?',$
			  label0='Cancel',label1='Close', title='Confirm close') then begin
					  self.continue_scanning=0
					  ;wait, 1.5
					  obj_destroy, self
			endif           
		endif
		if uname eq 'Start'    then begin
			message,/info,'Starting watching directory '+self.dirinit
			self->Log, 'Starting watching directory '+self.dirinit
			widget_control, self.top_base, timer=1  ; Start off the timer events for updating at 1 Hz
		endif
                if uname eq 'Reprocess'    then begin
                   widget_control, self.listfile_id, get_uvalue=list_contents
                   ind=widget_INFO(self.listfile_id,/LIST_SELECT)
                   
                   if ind[0] eq -1 then begin
                                ;error handling to prevent crash if someone selects 'reprocess
;selection' prior to pressing start.
                      message,/info, 'No files to reprocess. Press Start to load files in the directory being watched.'
                      ind=0
                   endif
                   
                   if list_contents[ind[0]] ne '' then begin
                      
                      self->Log,'User requested reprocessing of: '+strjoin(list_contents[ind], ", ")
                      self->handle_new_files, list_contents[ind] ;, /nowait
                   endif
	
		endif
		if uname eq 'View_one'    then begin
			widget_control, self.listfile_id, get_uvalue=list_contents

                        ind=widget_INFO(self.listfile_id,/LIST_SELECT)
            
                           if ind[0] eq -1 then begin
                                ;error handling to prevent
                                ;crash if someone selects 'View File' prior to pressing start.
                              message,/info, 'No file selected. Press Start to load files in the directory being watched.'
                              ind=0
                           endif

			if list_contents[ind[0]] ne '' then begin

				self->Log,'User requested to view: '+strjoin(list_contents[ind[0]], ", ")
				self.launcher_handle->launch, 'gpitv', filename=list_contents[ind[0]], session=45 ; arbitrary session number picked to be 1 more than this launcher
			endif
	
		endif
		if uname eq 'default_recipe'    then begin
			widget_control, self.seqid, sensitive=0
			self.user_template = ''
		endif
		if uname eq 'select_recipe'    then begin
			widget_control, self.seqid, sensitive=1
        	ind=widget_info(self.seqid,/DROPLIST_SELECT)
			self.user_template=((*self.templates).name)[ind]
	
		endif
		

	end 

	'WIDGET_LIST':begin
		if uname eq 'filelist' then begin
            if ev.clicks eq 2 then begin
              	ind=widget_INFO(self.listfile_id,/LIST_SELECT)
            
			  	if self.filelist[ind] ne '' then begin
					message,/info,'You double clicked on '+self.filelist[ind]
              		;print, self.filelist[ind]
	              	;CALL_PROCEDURE, self.commande,self.filelist(ind),mode=self.parsemode
				endif
            endif
		endif
	end
  	'WIDGET_KILL_REQUEST': begin ; kill request
		if dialog_message('Are you sure you want to close AutoReducer?', title="Confirm close", dialog_parent=ev.top, /question) eq 'Yes' then $
			obj_destroy, self
		return
	end
  	'WIDGET_DROPLIST': begin 
		if uname eq 'select_template' then begin
			print, self.templates[ind]
        	ind=widget_info(self.seqid,/DROPLIST_SELECT)
			self.user_template=self.templates[ind]
		endif

	end
	
    else:   begin
		print, "No handler defined for event of type "+tag_names(ev, /structure_name)+" in automaticreducer"
	endelse
endcase
end

;--------------------------------------
PRO automaticreducer::cleanup
	; kill the window and clear variables to conserve
	; memory when quitting.  The windowid parameter is used when
	; GPItv_shutdown is called automatically by the xmanager, if FITSGET is
	; killed by the window manager.


	; Kill top-level base if it still exists
	if (xregistered ('automaticreducer')) then widget_control, self.top_base, /destroy

	;self->parsergui::cleanup ; will destroy all widgets
	;reprocess_id = WIDGET_BUTTON(buttonbar,Value='Reprocess Selection',Uname='Reprocess', /tracking_events)

	heap_gc

	obj_destroy, self

end


;-------------------------------------------------
function automaticreducer::init, groupleader, _extra=_extra
	; Initialization code for automatic processing GUI

	self.dirinit=self->get_input_dir()
	self.maxnewfile=60
	self.alwaysexecute=1
	self.parsemode=1
	self.continue_scanning=1
	self.awaiting_parsing = ptr_new(/alloc)


	self.top_base = widget_base(title = 'GPI IFS Automatic Reducer', $
				   /column,  $
				   resource_name='GPI_DRP_AutoRed', $
				   /tlb_size_events,  /tlb_kill_request_events)


	base_dir = widget_base(self.top_base, /row)
	void = WIDGET_LABEL(base_dir,Value='Directory being watched: ', /align_left)
	self.watchdir_id =  WIDGET_LABEL(base_dir,Value=self.dirinit+"     ", /align_left)
	button_id = WIDGET_BUTTON(base_dir,Value='Change...',Uname='changedir',/align_right,/tracking_events)

	   
	base_dir = widget_base(self.top_base, /row)
	void = WIDGET_LABEL(base_dir,Value='Reduce new files:')    
	parsebase = Widget_Base(base_dir, UNAME='parsebase' ,ROW=1 ,/EXCLUSIVE, frame=0)
	self.parseone_id =    Widget_Button(parsebase, UNAME='one'  $
		  ,/ALIGN_LEFT ,VALUE='Automatically as each file arrives', /tracking_events)
	;self.parsenew_id =    Widget_Button(parsebase, UNAME='new'  $
		  ;,/ALIGN_LEFT ,VALUE='Flush filenames when new filetype',uvalue='new' )
	self.parseall_id =    Widget_Button(parsebase, UNAME='keep'  $
		  ,/ALIGN_LEFT ,VALUE='When user requests', /tracking_events ,sensitive=0) 
	widget_control, self.parseone_id, /set_button 

	self->scan_templates


	base_dir = widget_base(self.top_base, /row)
	void = WIDGET_LABEL(base_dir,Value='What kind of Recipe:')
	parsebase = Widget_Base(base_dir, UNAME='kindbase' ,ROW=1 ,/EXCLUSIVE, frame=0)
	self.b_simple_id =    Widget_Button(parsebase, UNAME='default_recipe'  $
	        ,/ALIGN_LEFT ,VALUE='Default automatic recipes',/tracking_events)
	self.b_full_id =    Widget_Button(parsebase, UNAME='select_recipe'  $
	        ,/ALIGN_LEFT ,VALUE='Specific recipe',/tracking_events, sensitive=1)
	widget_control, self.b_simple_id, /set_button 

	base_dir = widget_base(self.top_base, /row)
	self.seqid = WIDGET_DROPLIST(base_dir , title='Select template:', frame=0, Value=(*self.templates).name, $
		uvalue='select_template',resource_name='XmDroplistButton', sensitive=0)


	base_dir = widget_base(self.top_base, /row)
	void = WIDGET_LABEL(base_dir,Value='Default disperser if missing keyword:')
	parsebase = Widget_Base(base_dir, ROW=1 ,/EXCLUSIVE, frame=0)
	self.b_spectral_id =    Widget_Button(parsebase, UNAME='Spectral'  $
	        ,/ALIGN_LEFT ,VALUE='Spectral',/tracking_events)
	self.b_undispersed_id =    Widget_Button(parsebase, UNAME='Undispersed'  $
	        ,/ALIGN_LEFT ,VALUE='Undispersed',/tracking_events, sensitive=1)
	self.b_polarization_id =    Widget_Button(parsebase, UNAME='Polarization'  $
	        ,/ALIGN_LEFT ,VALUE='Polarization',/tracking_events, sensitive=1)
	
	widget_control, self.b_undispersed_id, /set_button 
  
          directory = gpi_get_directory('calibrations_DIR') 

        if file_test(directory+path_sep()+"shifts.fits") then begin
                shifts=readfits(directory+path_sep()+"shifts.fits")
                shiftx=strc(shifts[0],format="(f7.2)")
                shifty=strc(shifts[1],format="(f7.2)")
        endif else begin
                shiftx='0.'
                shifty='0.'
        endelse
  
  flexurebase = widget_base(self.top_base, /row)
  void = Widget_Label(flexurebase ,/ALIGN_LEFT ,VALUE='     Applying wavecal shift DX: ')
  self.shiftx_id = Widget_Text(flexurebase, UNAME='WID_DX'  $
                              ,SCR_XSIZE=56 ,SCR_YSIZE=24  $
                              ,SENSITIVE=1 ,XSIZE=20 ,YSIZE=1, value=shiftx, EDITABLE=1)
  void = Widget_Label(flexurebase ,/ALIGN_LEFT ,VALUE=' DY: ')
  self.shifty_id = Widget_Text(flexurebase, UNAME='WID_DY'  $
                                ,SCR_XSIZE=56 ,SCR_YSIZE=24  $
                                ,SENSITIVE=1 ,XSIZE=20 ,YSIZE=1, value=shifty, EDITABLE=1)
  button2_id = WIDGET_BUTTON(flexurebase,Value='Apply new shifts',Uname='changeshift',/align_right,/tracking_events)

	gpitvbase = Widget_Base(self.top_base, UNAME='alwaysexebase' ,ROW=1 ,/NONEXCLUSIVE, frame=0)
	self.view_in_gpitv_id =    Widget_Button(gpitvbase, UNAME='view_in_gpitv'  $
		  ,/ALIGN_LEFT ,VALUE='View new files in GPITV' )
	widget_control, self.view_in_gpitv_id, /set_button   
	;gpitvbase = Widget_Base(self.top_base, UNAME='alwaysexebase' ,COLUMN=1 ,/NONEXCLUSIVE, frame=0)
	self.ignore_raw_reads_id =    Widget_Button(gpitvbase, UNAME='ignore_raw_reads'  $
		  ,/ALIGN_LEFT ,VALUE='Ignore individual UTR/CDS readout files' )
	widget_control, self.ignore_raw_reads_id, /set_button   
	

	void = WIDGET_LABEL(self.top_base,Value='Detected FITS files:')
	self.listfile_id = WIDGET_LIST(self.top_base,YSIZE=10,  /tracking_events,uname='filelist',/multiple, uvalue='')
	widget_control, self.listfile_id, SET_VALUE= ['','','     ** not scanning anything yet; press the Start button below to begin **']


	lab = widget_label(self.top_base, value="History:")
	self.widget_log=widget_text(self.top_base,/scroll, ysize=8, xsize=60, /ALIGN_LEFT, uname="text_status",/tracking_events)

	buttonbar = widget_base(self.top_base, row=1)

	self.start_id = WIDGET_BUTTON(buttonbar,Value='Start',Uname='Start', /tracking_events)
	reprocess_id = WIDGET_BUTTON(buttonbar,Value='View File',Uname='View_one', /tracking_events)
	reprocess_id = WIDGET_BUTTON(buttonbar,Value='Reprocess Selection',Uname='Reprocess', /tracking_events)

	button3=widget_button(buttonbar,value="Close",uname="QUIT", /tracking_events)

	self.information_id=widget_label(self.top_base,uvalue="textinfo",xsize=450,value='                                                                                ')

	storage={$;info:info,fname:fname,$
		group:'',$
		self: self}
	widget_control,self.top_base ,set_uvalue=storage,/no_copy

	; Realize the widgets and run XMANAGER to manage them.
	; Register the widget with xmanager if it's not already registered
	if (not(xregistered('automaticreducer', /noshow))) then begin
		WIDGET_CONTROL, self.top_base, /REALIZE
		XMANAGER, 'automaticreducer', self.top_base, /NO_BLOCK
	endif

	
	RETURN, 1;filename

END
;-----------------------
pro automaticreducer::set_launcher_handle, launcher
	self.launcher_handle = launcher
end


;-----------------------
pro automaticreducer__define



stateF={  automaticreducer, $
    dirinit:'',$ ;initial root  directory for the tree
    user_template:'',$   ;command to execute when fits file double clicked
    scandir_id:0L,$ 
    continue_scanning:0, $
    parserobj:obj_new(),$
	launcher_handle: obj_new(), $	; handle to the launcher, *if* we were invoked that way.
    listfile_id:0L,$;wid id for list of fits file
    alwaysexecute_id:0L,$ ;wid id for automatically execute commande 
    alwaysexecute:0,$
    parseone_id :0L,$
    parsenew_id :0L,$
    parseall_id :0L,$
	b_simple_id :0L,$
	b_full_id :0L,$
	b_spectral_id :0L,$
	b_undispersed_id :0L,$
	b_polarization_id :0L,$
	shiftx_id:0L,$
	shifty_id:0L,$
	watchdir_id: 0L, $   ; widget ID for directory label display
	start_id: 0L, $		; widget ID for start parsing button
	view_in_gpitv_id: 0L, $
	ignore_raw_reads_id: 0L, $
    parsemode:0L,$
    information_id:0L,$
    maxnewfile:0L,$
    awaiting_parsing: ptr_new(),$ ;list of detected files 
    isnewdirroot:0,$ ;flag for  root dir
    button_id:0L,$ 
	previous_file_list: ptr_new(), $ ; List of files that have previously been encountered
    INHERITS parsergui} ;wid for detect-new-files button

end
