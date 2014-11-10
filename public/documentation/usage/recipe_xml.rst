Appendix: Recipe File XML Format
#####################################

In normal usage, recipes are typically created using the GUI, but they may be
edited by hand. We describe here the XML file format adopted for this. 

This file format is based on and extremely similar to, but not exactly identical with,
the format of Keck OSIRIS data reduction files ("DRFs").  
The following explanatory text is derived in large part
from the OSIRIS manual by Larkin et al., with a few modifications for
GPI.

In general, an XML document is a simple ASCII file composed of markup tags. For
OSIRIS DRFs, the most common tag is used to specify the operation of a
particular module such as::

   <module Name="Adjust Channel Levels" Skip="0"/>

In this example, the tag is enclosed in a < and /> to indicate the start and
end of the tag. Alternatively, we could have used a < and a > around the tag
contents, but then the complete tag would require an additional </module> to
specify the end of the tag. This would look like::

    <module Name="Adjust Channel Levels" Skip="0"></module>

The module is the element start tag and specifies the type of tag, in this case
a module call. Then Name and Skip specify "attributes" of the tag. It is up to
the pipeline to interpret these attributes. In many cases, tags can be nested,
and in fact a DRF is really just one <DRF> tag with many sub-tags. Generally
white space such as spaces and carriage returns are ignored.

To add a comment to an xml file surround the text in a <!-- and a --> such as in this example::
        <!--This is a comment -->

Recipe "DRF" XML tags
-----------------------

Now we"ll begin looking at DRF specific XML tags. All DRFs must start with a header specifying the flavor of xml to use::
        <?xml version="1.0" encoding="UTF-8"?>

This is then followed by a DRF tag which must include the ReductionType attribute. So an example DRF tag might look like::
        <DRF ReductionType="SpectralScience">

Note that the > does not end the tag and future tags are really attributes
within the DRF tag. At the end of the file, you must close the DRF tag with a
</DRF>. See below for examples.

After the DRF tag, you need to define the data frames that should be processed.
This is done with the DATASET tag. It must include an InputDir attribute and
then a series of FITS attributes that list the filenames. Optionally you can
include a Name attribute and an outputdir tag, although name is completely
optional, and the outputdir is more commonly specified in the specific output
modules. So an example of the DATASET tag might be::

  <dataset InputDir="/archive/osiris/051123/SPEC/raw" >
  	<fits FileName="s051123_a013001.fits" /> 
  	<fits FileName="s051123_a013003.fits" /> 
  	<fits FileName="s051123_a014001.fits" />
  	<fits FileName="s051123_a014003.fits" /> 
  	<fits FileName="s051123_a015001.fits" /> 
  </dataset>
 
The typical DRF is then composed of a series of items specifying the order of the reduction steps as well as any calibration files and parameters that are needed. The name of the module must be specified using the Name attribute. These names are not negotiable and the exact name must be used. Examples::

        <module name="Extract Spectral Datacube" Save="0" />
        <module name="Simple SSDI" L1Min="1.55" L1Max="1.57" L2Min="1.60" L2Max="1.65" k="1.0" Save="1" gpitv="5" />

Common parameters
------------------

Each module can have an arbitrary list of parameters, just like keywords in
IDL. However, due to the required way the XML file is parsed, all attributes
must be strings enclosed in quotes. This is true even for simple integer
values.

If the step needs a calibration file (i.e., Subtract Dark Frame, Extract
Spectra) the attribute will look like::

   CalibrationFile="/directory/SPEC/calib/calibration_file.fits"

Typically, you want calibration files to be retrieved automatically from the :ref:`calibdb`::

   CalibrationFile="AUTOMATIC"


If you decide to re-run a DRF and would like to skip a particular module, the
easiest way is with the Skip attribute. Set it to "1" in order to skip the
file, and set it back to "0" to execute the file. The default is "0" and is not
required.  ::

        Skip="1"

Many modules allow the output data to be piped to a GPItv window for immediate display. Just set the gpitv argument equal to the session number of the window to display in::

        gpitv="3"

Others allow the user to save the results of this step (distinct from saving the final output at the end of the whole list of steps)::

        save="1"

Other attributes are used by a subset of modules, providing specific parameters for each step, and are described :ref:`elsewhere <primitives>`. 

Example DRF 
-------------------


::
  
  <?xml version="1.0" encoding="UTF-8"?>
  <DRF LogPath="/Users/mperrin/projects/GPI/pipnew/drp_code" ReductionType="Final">
  <dataset InputDir="/Users/mperrin/projects/GPI/data" Name="" OutputDir="/Users/mperrin/projects/GPI/pipnew/drp_code">
     <fits FileName="Ima10_H.fits" />
     <fits FileName="Ima11_H.fits" />
     <fits FileName="Ima12_H.fits" />
     <fits FileName="Ima13_H.fits" />
     <fits FileName="Ima14_H.fits" />
     <fits FileName="Ima15_H.fits" />
     <fits FileName="Ima16_H.fits" />
    <fits FileName="Ima17_H.fits" />
     <fits FileName="Ima18_H.fits" />
  </dataset>
  <module name="Read Wavelength Calibration" CalibrationFile="/Users/mperrin/GPI/pipnew/drp_code/Ima2_HH-wavcal-comb.fits" />
  <module name="Display Data with GPITV" gpitv="1" />
  <module name="Extract Spectral Datacube" Save="0" />
  <module name="Divide spectral data by flat" CalibrationFile="/Users/mperrin/projects/GPI/pipnew/drp_code/Ima4_Hflat.fits" Save="1" gpitv="2" />
  <module name="Interpolate Wavelength Axis" Save="1" gpitv="2" />
  <module name="Simple SSDI" L1Min="1.55" L1Max="1.57" L2Min="1.60" L2Max="1.65" k="1.0" Save="1" gpitv="5" />
  <module name="Accumulate Images" Method="OnDisk" />
  <module name="ADI based on Marois et al" numimmed="3" nfwhm="1.5" Save="0" gpitv="10" />
  <module name="Median ADI data-cubes" Save="1" gpitv="10" />
  </DRF>


