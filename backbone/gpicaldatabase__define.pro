;+
; NAME: gpicaldatabase__define
;
; 	A database to track calibration code for GPI, and automatically find
; 	the best calibrations for a given file if requested.
;
; INPUTS:
; KEYWORDS:
; OUTPUTS:
;
; 	Creates and updates calibration files in the directory of choice. 
; 	By default it keeps duplicates in both TXT and FITS formats.
; 	The FITS file is what is really used; the TXT is just for ease of 
; 	reading by humans. 
;
; HISTORY:
; 	Began 2010-01-26 17:11:04 by Marshall Perrin 
; 	... many updated not recorded here ...
; 	2012-10-10 MP: Added restriction based on IFS cooldown start/stop dates
;-

function gpicaldatabase::new_calfile_struct
; what info about a given calibration file do we want?
calfile = { $
			path: "", $
			filename: "", $
			type: "", $
			prism: "", $
			filter: "", $
			lyot: "", $
			apodizer: "", $
			itime: 0.0, $
			JD: 0.0d, $
			inport: "", $
			readoutmode: "", $
			other: "", $
			valid: 1b}

	return, calfile
end

pro gpicaldatabase::log, messagestr, _extra=_Extra
     if obj_valid(self.backbone) then self.backbone->Log, "GPICALDB: "+messagestr, _extra=_extra else message,/info, messagestr
end

FUNCTIOn gpicaldatabase::get_calibdir
	return, self.caldir
end

function gpicaldatabase::get_data
     return, self.data
end

;----------
; Initialization
FUNCTION gpicaldatabase::init, directory=directory, dbfilename=dbfilename, backbone=backbone
	; Open and scan the directory of calibration data
	
	if ~(keyword_set(dbfilename)) then dbfilename="GPI_Calibs_DB.fits"

	; Determine where calibration files live
	if ~(keyword_set(directory)) then begin
		directory = gpi_get_directory('calibrations_DIR') 
	endif
	print, ""
	print, "  Calibration Files Directory is "+directory
	print, ""

	self.caldir = directory
	self.dbfilename = dbfilename
	if arg_present(backbone) then self.backbone=backbone ; Main GPI pipeline code?


	;--- Read in calibrations database
	caldbfile = self.caldir+path_sep()+self.dbfilename
	if ~file_test(caldbfile) then begin
		self->Log,"Nonexistent calibrations DB filename requested! "
		self->Log,"no such file: "+self.caldir+path_sep()+self.dbfilename
		self->Log,"Creating blank calibrations DB"
		self.data = ptr_new() ;self->new_calfile_struct)
		self.nfiles=0
	endif else begin

		; TODO add file locking to prevent multiple copies from fighting over the
		; DB?
		
		data = mrdfits(caldbfile,1)
		; TODO error checking that this is in fact a calib DB struct?
		;
		; FIXME MRDFITS does not remove trailing whitespace added to every field
		; by how MWRFITS writes out the table. So we have to trim every field
		; here?
		for i=0,n_tags(data)-1 do if size(data.(i),/TNAME) eq "STRING" then data.(i) = strtrim(data.(i),2)
		self.data = ptr_new(data,/no_copy)
		self.nfiles = n_elements(*self.data)
		self->Log, "Loaded Calibrations DB from "+caldbfile,depth=1
		self->Log, "Found "+strc(self.nfiles)+ " entries", depth=1
	


		self->verify


	endelse 

	;--- read in list of cooldown dates for the IFS
	;    This is used to restrict which sets of calibration files are
	;    worth looking at when matching. 
	readcol, gpi_get_directory('GPI_DRP_CONFIG_DIR')+path_sep()+'ifs_cooldown_history.txt', year, month, date, count=count
	if count gt 0 then begin
		jds = dblarr(n_elements(year))
		for i=0,n_elements(year)-1 do jds[i] = julday(month[i], date[i], year[i]) 
		self.ifs_cooldown_jds = ptr_new(jds)
	endif else begin
		self.ifs_cooldown_jds = ptr_new([1])
	endelse





	return, 1

end

;----------
; Scan through each file in the DB and make sure it
; exists (checks against user deleting a cal file after it was created)
pro gpicaldatabase::verify
	; Right now this just verifies the file still exists, without doing any
	; actual checking against its contents. TBD?

	if self.nfiles eq 0 then return
	
	n = n_elements(*self.data)
	any_invalid = 0
	for i=0L,n-1 do begin

		;calfile = strtrim((*self.data)[i].path +path_sep()+ (*self.data)[i].filename,2)
		calfile = (*self.data)[i].path +path_sep()+ (*self.data)[i].filename
		if ~file_test( calfile) then begin
			message,/info,"Missing Cal File: "+calfile
			(*self.data)[i].valid=0b
			any_invalid=1
		endif

	endfor 

	if any_invalid then begin
		self->Log, "There were one or more calibration files in the DB which could not be found",depth=0
		self->Log, "Those files have been marked as invalid for now. But you should probably ",depth=1
		self->Log, "re-scan the database to re-create the index file!",depth=1
	endif else begin
		self->Log, "  All "+strc(n)+" files in Cal DB verified OK.",depth=1
	endelse


end

;----------
; write out update calibration DB
PRO gpicaldatabase::write

	if self.nfiles eq 0 then return

	; write a version in FITS for computers to read
	calfile = self.caldir+path_sep()+self.dbfilename
	mwrfits, *self.data, calfile, /create ; overwrite!
	message,/info, " Writing to "+calfile

	; write a version in TXT for humans to read
	calfile_txt = strepex(calfile, ".fits", ".txt")
	d = (*self.data)
	; TODO sort??
	mlen_p = max(strlen(d.path))+3
	mlen_f = max(strlen(d.filename))+3

	firstline = string("#PATH", "FILENAME", "TYPE", "DISPERSR", "IFSFILT", "APODIZER", "LYOTMASK", "INPORT", "ITIME", "READMODE", "JD", "OTHER", $
			format="(A-"+strc(mlen_p)+", A-"+strc(mlen_f)+", A-30,  A-10,     A-5     , A-8,         A-8,       A-6,     A-15,    A-15,   A-15,   A-10)")
	forprint2, textout=calfile_txt, d.path, d.filename,  d.type, d.prism, d.filter, d.apodizer, d.lyot, d.inport, d.itime, d.readoutmode, d.jd, d.other, $
			format="(A-"+strc(mlen_p)+", A-"+strc(mlen_f)+", A-30,  A-10,     A-5     , A-8,         A-8,       A-6,     D-15.5,  D-15.5, A-15, A-10)", /silent, $
			comment=firstline
	message,/info, " Writing to "+calfile_txt

	self.modified=0 ; Calibration database on disk now matches the one in memory

end

;----------
PRO gpicaldatabase::rescan ; an alias
	self->rescan_directory 
end

; Create a new calibrations DB by reading all files in a given directory
PRO gpicaldatabase::rescan_directory
	files = file_search(self.caldir+path_sep()+"*.fits")
	nf = n_elements(files)
	self->Log, "Rescanning all FITS files in directory "+self.caldir
	ptr_free,self.data
	self.nfiles=0
	for i=0L,nf-1 do begin
		;self->Log, "Attempting to add file "+files[i]
		status = self->add_new_cal( strtrim(files[i],2), /delaywrite)
	endfor 
	if self.modified then self->write ; save updated cal DB to disk.
  self->Log, "Database rescanning completed! "
  print, "Database rescanning completed! "

end



;----------
; add a new calibration file
Function gpicaldatabase::add_new_cal, filename, delaywrite=delaywrite ;, header=header
	; HISTORY:
	; 2012-01-27: Updated for MEF files -MP
	; 2012-06-12: Added /delaywrite for improved performance in rescan. -MP
	;
	;COMMON APP_CONSTANTS
		
	OK = 0
	NOT_OK = -1

	; Check the file exists
	if ~file_test(filename) then begin
		message,/info, "Supplied file name does not exist: "+filename
		return, Not_OK
	endif

	fits_data = gpi_load_fits(filename,/nodata) ; only read in headers, not data.

	; 	if not a valid cal then return...
	if strupcase(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header,"ISCALIB")) ne "YES" then begin
		self->Log, "File "+filename+" does not appear to be a valid GPI calibration file."
		self->Log, "   Ignoring that file!"
		return, 0
	endif

	filename = strtrim(filename,2)

	; Read in the relevant information from the header
	;
	
	newcal = self->cal_info_from_header(fits_data)
	newcal.path= file_dirname(filename)
    newcal.filename = file_basename(filename)
	; add info to archive
	; 	overwrite if already present, otherwise add new
	if self.nfiles eq 0 then begin
		self.data = ptr_new(newcal)
		self->Log, "New entry added to cal DB for "+newcal.filename
	endif else begin
		; test if this file already exists in the cal DB?	
		wmatch = where( ((*self.data).path eq newcal.path ) and ((*self.data).filename eq newcal.filename), matchct)
		if matchct gt 0 then begin ; Update existing entry
			(*self.data)[wmatch] = newcal
			self->Log, "Updated entry in cal DB for "+newcal.filename
		endif else begin			; add new entry
			*self.data = [*self.data, newcal]
			self->Log, "New entry added to cal DB for "+newcal.filename
		endelse
	endelse
	self.nfiles += 1

	self.modified=1

	; force write right away
	if keyword_set(self.modified) and not keyword_set(delaywrite) then begin
		self->write
		self.modified=0
	endif

	Return, OK

end

;--------
; Parse out the relevant header information that is useful for matching a given
; file to its calibration data. This gets a large set of keywords, since it has
; to be the union of values that are relevant for all files. 
function gpicaldatabase::cal_info_from_header, fits_data
	; 	Note that the fits_data argument should be a structure as returned by
	; 	gpi_load_fits.
	;
	;
	; Read in the relevant information from the header
	thisfile = self->new_calfile_struct()

	; check what kind of file it is
	thisfile.type = gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, "FILETYPE", count=count,/silent)
	; Don't print any alert for missing FILETYPE - this is not present in raw
	; data
	;if count ne 1 then message,/info, "Missing keyword: FILETYPE"

	filtkeys =['IFSFILT','FILTER1','FILTER']
	for i=0,n_elements(filtkeys)-1 do begin
		thisfile.filter = gpi_simplify_keyword_value(strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, filtkeys[i], count=count)))
		if count eq 1 then break
	endfor
	if count ne 1 then begin 
	    message,/info, "Missing keyword: IFSFILT"
        endif

	thisfile.prism= gpi_simplify_keyword_value(strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, "DISPERSR", count=count3)))
        if count3 ne 1 then message,/info, "Missing keyword: DISPERSR"

	thisfile.apodizer= strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, "APODIZER", count=count))
	if count ne 1 then message,/info, "Missing keyword: APODIZER"

	thisfile.itime = (gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, "ITIME", count=count3))
        if count3 ne 1 then message,/info, "Missing keyword: ITIME"

	thisfile.lyot= strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, "LYOTMASK", count=count))
	if count ne 1 then message,/info, "Missing keyword: LYOTMASK"  ; Missing in all DST files pre 2010-01-28!
	
	thisfile.inport = strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, "INPORT", count=count))
	; no INPORT in I&T data yet. 
	;if count ne 1 then message,/info, "Missing keyword: INPORT"

	; this one's complicated enough to be a function. 
	thisfile.readoutmode = self->get_readoutmode_as_string(fits_data)

	; possibly modify this to use the MJD keywords? (once present from
	; Gemini GDS)
	; No - DATE-OBS and UTSTART are written by the IFS, thus are the original &
	; most accurate time stamp
	dateobs =  strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, "DATE-OBS"))+$
		   "T"+strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header,"UTSTART"))
	thisfile.jd = date_conv(dateobs, "J")

	return, thisfile
end



;----------
; Find which calibration file in the DB best matches
; the need for a given routine
; 
; This routine extracts the relevant parameters from a supplied FITS header and
; tehen calls get_best_cal to do the actual matching.
function gpicaldatabase::get_best_cal_from_header, type, priheader, extheader, _extra=_extra
	; Parameters:
	; 	type		what kind of a dark is requested? String name. 
	; 	priheader, extheader	like the names imply


	fits_data = {pri_header: ptr_new(priheader), ext_header: ptr_new(extheader)}
	return, self->get_best_cal( type, fits_data)


end

;----------
; Find which calibration file in the DB best matches
; the need for a given routine
function gpicaldatabase::get_best_cal, type, fits_data, date, filter, prism, itime=itime, $
	verbose=verbose



	;common APP_CONSTANTS
	OK = 0
	NOT_OK=-1

	if self.nfiles eq 0 then message, "ERROR: --NO CAL FILES IN DB--"

	;---- Organize a catalog of different types of calibration files ----	
	; Build a structure defining all the potential calibrator types, specifying
	;  a) a name (short and used in code)
	;  b) a long description for human consumption (and which is used in the Cals DB
	;  c) how do we identify the best match?
	
	; 2010-01-10 MDP: why does the code try to match dark files using itimeFilt?
	; For dark images, the filter does not matter. I'm going to change this to
	; just 'itime' unless someone has another opinion?

	types_str =[['dark', 'Dark', 'itimeReadmode'], $
			  	['wavecal', 'Wavelength Solution Cal File', 'FiltPrism'], $
				['flat', 'Flat field', 'FiltPrism'], $
				;['flat', 'Flat field', 'FiltPrism'], $
				['badpix', 'Bad Pixel Map', 'typeonly'], $
				['plate', 'Plate scale & orientation', 'typeonly'], $
				['spotloc', 'Spot Location Measurement', 'FiltOnly'], $
				['Gridratio', 'Grid Ratio', 'FiltOnly'], $
				['Fluxconv', 'Fluxconv', 'FiltPrism'], $
				['telluric', 'Telluric Transmission', 'FiltPrism'], $
				['polcal', 'Polarimetry Spots Cal File', 'FiltPrism'], $
				['instpol', 'Instrumental Polarization', 'FiltPrism'], $
				['distor', 'Distortion Measurement', 'typeonly'], $
				['', '', 'FiltPrism'], $
				['', '', ''], $
				['', '', '']]
	; reformat the above into a struct array.
	aa = {type_struct, name: 'dark', description:'Dark', match_on:"itimeFilt"}
	types = replicate(aa, (size(types_str))[2])
	types.name=reform(types_str[0,*])
	types.description=reform(types_str[1,*])
	types.match_on=reform(types_str[2,*])



	itype = where(types.name eq type, matchct)
	if matchct ne 1 then begin
		message, "Unknown or invalid type of calibration file requested: '"+type+"'.",/info
		return, NOT_OK
	end

	if keyword_set(verbose) then message,/info, "Finding Calibration File for "+ types[itype].description +" using selection on "+types[itype].match_on

	wm= where(strmatch((*self.data).type, types[itype].description+"*",/fold),cc)
	if cc eq 0 then begin
		self->Log, "CALIBS DB ERROR: --NO FILES FOR "+types[itype].description+" IN DB--",depth=1
		return, NOT_OK
	endif 


	;---- Get the info from the current file we're going to be matching on
	newfile = self->cal_info_from_header(fits_data)
	date=newfile.jd
	filter=newfile.filter
	prism=newfile.prism
	itime=newfile.itime
	readoutmode=newfile.readoutmode ;self->get_readoutmode_as_string(fits_data)

	;---- optional: restrict based on dates of IFS cooldown runs (so 
	if gpi_get_setting('caldb_restricts_by_cooldown', /bool, default=1,/silent) then begin
		calfiles_table = (*self.data)
		
		; find the JD range corresponding to the IFS cooldown run for that data
		wstart = where(*self.ifs_cooldown_jds lt newfile.jd, countstart)
		if countstart gt 0 then cooldown_start = max( (*self.ifs_cooldown_jds)[wstart]) else cooldown_start=1
		wstop= where(*self.ifs_cooldown_jds gt newfile.jd, countstop)
		if countstop gt 0 then cooldown_stop = min( (calfiles_table.JD)[wstop]) else cooldown_stop=1e7

		startday_str = strmid(date_conv(cooldown_start,'FITS'), 0, 10)
		stopday_str = strmid(date_conv(cooldown_stop,'FITS'), 0, 10)
		if cooldown_stop eq 1e7 then stopday_str = "present"

		wCorrectCooldown = where((calfiles_table.JD ge cooldown_start) and (calfiles_table.JD le cooldown_stop), correctcount)
		if correctcount eq 0 then begin
			self->Log, "CALIBS DB ERROR: --NO FILES AVAILABLE IN DB for IFS cooldown between "+startday_str+" to "+stopday_str+" --",depth=1
			return, NOT_OK
		endif 

		; restrict based on that range
		calfiles_table = (*self.data)[wCorrectCooldown]

		wm= where(strmatch(calfiles_table.type, types[itype].description+"*",/fold),cc)
		if cc eq 0 then begin
			self->Log, "CALIBS DB ERROR: --NO FILES FOR "+types[itype].description+" IN DB for the IFS cooldown between "+startday_str+" to "+stopday_str+"--",depth=1
			return, NOT_OK
		endif 



	endif else begin
		; Use all calibration files.
		calfiles_table = (*self.data)


	endelse



	case types[itype].match_on of 
	'typeonly': begin
		 imatches= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold), cc)
		 errdesc = 'of the correct type'
	end

	'itime': begin
	    imatches= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold) and $
	   		(calfiles_table.itime) eq itime,cc)
		errdesc = 'with same ITIME'
		; FIXME if no exact match found for itime, fall back to closest match
		if cc eq 0 then begin
			self->Log, "No exact match found for ITIME, thus looking for closesd approximate mathc instead",depth=3
	    	imatches_typeonly= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold))
			deltatimes = calfiles_table[imatches_typeonly].itime - itime

			mindelta = min( abs(deltatimes), wmin)
			imatches= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold) and $
				            (calfiles_table.itime) eq calfiles_table[wmin[0]].itime,cc)
			self->Log, "Found "+strc(cc)+" approx matches with ITIME="+strc(calfiles_table[wmin[0]].itime)


		endif

	end
	'itimeReadmode': begin
	    imatches= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold) and $
	   		((calfiles_table.readoutmode) eq readoutmode ) and $
	   		(calfiles_table.itime) eq itime,cc)
		errdesc = 'with same ITIME'
		; FIXME if no exact match found for itime, fall back to closest match
		if cc eq 0 then begin
			self->Log, "No exact match found for ITIME, thus looking for closesd approximate mathc instead",depth=3
	    	imatches_typeonly= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold))
			deltatimes = calfiles_table[imatches_typeonly].itime - itime

			mindelta = min( abs(deltatimes), wmin)
			imatches= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold) and $
				            (calfiles_table.itime) eq calfiles_table[wmin[0]].itime,cc)
            self->Log, " Found "+strc(cc)+" approx matches with ITIME="+strc(calfiles_table[wmin[0]].itime)


		endif

	end
	
	 'itimeFilt': begin
      	imatches= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold) and $
        ((calfiles_table.itime) eq itime) and $
        ((calfiles_table.filter) eq filter) ,cc) 
    	errdesc = 'with same ITIME and FILTER'
  	end
	'FiltPrism': begin
		 imatches= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold) and $
	   		((calfiles_table.filter) eq filter ) and $
	   		((calfiles_table.prism) eq prism) ,cc)
		 errdesc = 'with same DISPERSR and FILTER'
	end
	'FiltOnly': begin
     	imatches= where( strmatch(calfiles_table.type, types[itype].description+"*",/fold) and $
        ((calfiles_table.filter) eq filter )  ,cc)
     	errdesc = 'with same FILTER'
  	end
	endcase
    
	if cc eq 0 then begin
		message, "ERROR: --No matching cal files "+errdesc+" as requested in DB--",/info
		void=error('ERROR: --No matching cal files '+errdesc+' as requested in DB--')
		return, NOT_OK
	endif
	if keyword_set(verbose) then message,/info, "Found "+strc(cc)+" possible cal files; selecting best based on closest date."


	timediff=min(abs( (calfiles_table.JD)[imatches] - date ),minind)
	if keyword_set(verbose) then message,/info, "Closest date offset is "+strc(timediff)
	;combinaison of wav.cal. has same timediff than the most recent wav.cal of the combinaison
	;so, keep only the combinaison (TO DO: use keyword DATAFILE instead of suffix filename?)
	ibests=where(abs( (calfiles_table.JD)[imatches] - date ) eq timediff,cc)

	if cc gt 1 then begin
  		ibest = imatches[minind]
  	endif else begin
	  	ibest = imatches[minind]
	endelse
	
    bestcalib=(calfiles_table.PATH)[ibest]+path_sep()+(calfiles_table.FILENAME)[ibest]
	if keyword_set(verbose) then message,/info, "Returning best calib= "+bestcalib

    self->Log, "Returning best cal file= "+bestcalib,depth=3
	
	return, bestcalib


end


;----------

function gpicaldatabase::get_readoutmode_as_string, fits_data
     if gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, 'INSTRSUB') eq 'GPI IFS Pupil' then begin
         readoutmode = "Pupil_Viewer:"
     endif else begin
         samplingMode = strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, 'SAMPMODE', count=count))
         if count ne 1 then begin message,/info, "Missing keyword: SAMPMODE" & samplingMode = '0' & endif
         totReads = strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, 'READS', count=count))
         if count ne 1 then begin message,/info, "Missing keyword: READS" & totreads = '0' & endif
         numGroups = strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, 'NGROUP', count=count))
         if count ne 1 then begin message,/info, "Missing keyword: NGROUP" & numGroups = '0' & endif
         datasec = strc(gpi_get_keyword(*fits_data.pri_header, *fits_data.ext_header, 'DATASEC', count=count))
         if count ne 1 then begin message,/info, "Missing keyword: DATASEC" & datasec = '[0:0,0:0]' & endif

         readoutmode = samplingMode+"_"+totReads+"_"+numGroups+"_"+datasec
     endelse
     
     return, readoutmode
end

;----------

pro gpicaldatabase::get_readoutmode_from_string, readoutmode, samplingMode=samplingMode,$
                  numReads=numReads,numGroups=numGroups,startX=startX, startY=startY, endX=endX, endY=endY

	regex = '([[:digit:]])_([[:digit:]]+)_([[:digit:]])_\[([[:digit:]]+):([[:digit:]]+),([[:digit:]]+):([[:digit:]]+)\]'
	res = stregex(readoutmode,regex,/subexpr,/extract)

	samplingMode = long(res[1,*])
	totReads = float(res[2,*])
	numGroups = float(res[3,*])
	startX = float(res[4,*]) - 1.
	endX = float(res[5,*]) - 1.
	startY = float(res[6,*]) - 1.
	endY = float(res[7,*]) - 1.

	nchan = fltarr(n_elements(readoutmode)) + 32.
	inds = where((startX ne 0) or (endX ne 2047) or (startY ne 0) or (endY ne 2047),cc)
	if cc gt 0 then nchan[inds] = 1.

	tframe = ((endX-startX+1)/nchan+7)*(endY-startY+2)*10e-6

	;;determine different modes (assume single unless proven otherwise)
	cdss = where((samplingMode eq 2) or (samplingMode eq 3),ccds)
	utrs = where(samplingMode eq 4,cutr)

	;;numReads - for single, this is 1, for CDS & MCDS it's half the total
	;;           number of reads, for UTR its the total number of reads/numGroups
	numReads = totReads
	if ccds gt 0 then numReads[cdss] /= 2.
	if cutr gt 0 then numReads[utrs] = numReads[utrs]/numGroups[utrs]

end

;----------
PRO gpicaldatabase__define

void = {gpicaldatabase, $
		backbone: obj_new(), $
		caldir: "", $
		dbfilename: "",$
		data: ptr_new(), $
		ifs_cooldown_jds: ptr_new(), $
		nfiles: 0, $
		modified: 0 $
	}


end
