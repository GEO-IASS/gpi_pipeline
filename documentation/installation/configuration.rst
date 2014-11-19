.. _configuring:

Configuring the Pipeline
=============================

The GPI data reduction pipeline relies on a variety of configuration
information. This can roughly be divided into three sections:

1. :ref:`Pipeline environment variables <config-envvars>` define some basic locations of interest in the
   file system.

2. :ref:`Pipeline configuration files <config-textfiles>`  define various options and settings. This
   follows the paradigm common to many Unix programs in that there is a
   system-wide configuration file that defines defaults, and then
   each user may optionally have a config file in their home directory to change
   values away from the defaults. In many cases, the default settings will be
   fine without being changed.
   
 
3. :ref:`Pipeline ancillary data <config-ancillarydata>` contains pipeline settings that should rarely, if ever, need to be changed (e.g. the definitions of constants such as the speed of light).
  
.. comments 
		.. note::
  		  When installing the pipeline for the first time, you will (at a minimum) need
    to set some file paths as appropriate for your site, most easily by defining environment variables as described below. 
    You may also wish to create a user settings file and
    edit its settings if you wish to change any of the defaults, but this is not
    required. 


Installing the pipeline for the first time requires several paths to be defined via
environment variables. Only three paths are explicitly required to be set; the
rest have default settings that should work for the majority of users (but may
be changed if desired).  

Automated Setup
-----------------------------------
For most users, the automated setup should be sufficient and there should be no need to configure things manually. 

These installation scripts will guide you through the setup process and will automatically configure most of the settings for you. It does require you to verify or enter a few filepaths to ensure they point to the correct directories. The setup script writes out a configuration file to your home directory to save these settings. If you wish to change the file paths after running the setup script, simply edit that text file.

The setup script will ask you where you would like to store your GPI data. This can be any directory path. The script will automatically create some subdirectories inside the data directory for raw files, reduced files, log files, and so on. 

The setup script appropriate for your OS will be located in the ``pipeline/scripts`` directory.


.. admonition:: Mac OS and Linux

    .. image:: icon_mac2.png

    .. image:: icon_linux2.png
  
 On Mac OS and Linux, open up a terminal and go to the ``pipeline/scripts`` directory. Then you will want to run the bash script ``gpi-setup-nix`` with the following command::

 > bash gpi-setup-nix

 Follow the instructions given by the installation script. The relevant settings are written to a file ``.gpienv`` in your home directory. You will need to restart your terminal application for the installation to take effect.

 If everything went well, you can proceed to starting up the pipeline: :ref:`first-startup`.

 If the automated setup did not work properly, you may need to install the pipeline manually: :ref:`config-manual`.

.. admonition:: Windows

    .. image:: icon_windows2.png

 **For Windows Vista and newer**, open up the ``pipeline/scripts`` directory and double click on ``gpi-setup-windows.bat`` to start the installation script. 

 Follow the instructions given by the installation script. If everything went well, you can proceed to starting up the pipeline: :ref:`first-startup`.

 If the automated setup did not work properly, you may need to install the pipeline manually: :ref:`config-manual`.

 **For Windows XP users**, the automated installation script will work with some changes to the script itself. Open up ``gpi-setup-windows.bat`` in a text editor and follow the instructions inside to modify the script for Windows XP.  Alternatively, Windows XP and older users can configure the pipeline manually: :ref:`config-manual`. (But you should upgrade to a more recent version of Windows in any case!)



Here is an example of a session using the automated installation script to install from source code on a Mac. Some of the prompts will be slightly different depending on OS, and source vs. compiled installations. ::

    **************************************************************************************
    ******* GPI Data Pipeline Environment Setup Script for Unix (Mac OS X) & Linux *******
    **************************************************************************************
     This appears to be an installation from source code.

    WARNING: IDL is not in $PATH. Please make sure IDL is installed
     and not aliased. An aliased IDL may not work with the gpi-pipeline
     shortcut, but you can still launch the pipeline manually.


     We will need to set up some directories. Please provide the
     correct directory (absolute paths!) for each of the following
     environment variables. This program will attempt to guess a location
     that may or may not be right. PLEASE CHECK AND ADJUST THESE AS DESIRED
     FOR YOUR COMPUTER.

     Finding the location of the GPI pipeline directory. This should be the
     top-level directory of the downloaded and unzipped pipeline, containing
     contain folders such as 'scripts', 'config', & 'recipe_remplates'
     among others.

    For GPI_PIPELINE_DIR, is '/Users/myusername/GPI/gpi_pipeline_1.2.1_r3478_source/pipeline' the correct path (y|n)? y

     Finding the location of the GPI external libraries directory.
     This directory should contain the pipeline dependencies ('pipeline_deps').
     EXTERNDIR automatically located at /Users/myusername/GPI/gpi_pipeline_1.2.1_r3478_source/external. No user input needed.


     Looking up default directory to set up a GPI Data directory.
     Please change this to a folder you intend in store GPI data in. This script
     will automatically create subdirectories for Raw data, Reduced data, log files,
     and so on. If you wish to adjust these paths later, you may do so by editing
     the $HOME/.gpienv file.

    For DATADIR, is '/Users/myusername/GPI/gpi_pipeline_1.2.1_r3478_source/data' the correct path (y|n)? y

    GPI Pipeline directory will be /Users/myusername/GPI/gpi_pipeline_1.2.1_r3478_source/pipeline
    GPI External Libraries directory will be /Users/myusername/GPI/gpi_pipeline_1.2.1_r3478_source/external
    GPI Data directory will be /Users/myusername/GPI/gpi_pipeline_1.2.1_r3478_source/data
    Creating GPI configuration file in /Users/myusername/.gpienv
    Setting up folders inside your GPI Data Directory (if necessary)...


    Writing GPI Settings to /Users/myusername/.gpienv

     The .gpienv file needs to be executed to set environment variables each
     time you start a new terminal. Would you like this setup script to
     modify your .cshrc file to automatically source .gpienv when you
     open a terminal?

    Should this script edit your .cshrc to source $HOME/.gpienv? (y|n) y
    Modifying /Users/myusername/.cshrc to automatically run /Users/myusername/.gpienv

    ****************    Installation Complete!    ***************
     You will need to restart your terminal to run gpi-pipeline.
    *************************************************************






If you have successfully ran the automated setup script, you can skip ahead to  :ref:`first-startup`, or read on to understand what the automated setup is doing under the hood, and/or how you can manually adjust file paths if you want to customize your installation.

.. _config-manual:

How to Set Environment Variables Manually
-----------------------------------------------

.. note::
  The example scripts described in the following section are now mostly obsolete due to the automated setup script.
  The following text is kept here just for reference right now, and to describe how to set up environment variables
  manually for users who do not know how to do so. But really, most people should can let the automated setup script
  take care of this all. 

The pipeline includes some example scripts demonstrating how to set environment variables, located in the ``scripts`` subdirectory of the
pipeline installation.  As an alternate to using the automated setups script,  users may take the example script for their selected shell and modify it for their local directory paths.

 * ``setenv_GPI_sample.bash``: Example environment variable setup script for sh or bash Unix shells
 * ``setenv_GPI_sample.csh``: Example environment variable setup script for csh or tcsh Unix shells
 * ``setenv_gpi_windows.pro``: Example setup IDL procedure for use on Windows.


The following sections walk the user through the manual pipeline configuration.

If you already know how to set environment variables on your computer, skip to :ref:`config-envvars`.

.. admonition:: Mac OS and Linux

    .. image:: icon_mac2.png

    .. image:: icon_linux2.png
  
 On Mac OS and Linux, environment variables are generally set by shell
 configuration "dot files" in your home directory.  Example shell scripts that
 set the variables required by the pipeline are provided in the
 pipeline/scripts directory. Although it is possible to edit the scripts in
 this directory, they will be overwritten when you update the pipeline.
 Therefore, the best approach is to create a local copy. Here, we walk you
 through the setup process.

 The first thing to do is determine shell you are currently using. To do so, run the following in a terminal (note that the > represents the prompt and should not be entered in the command):

 > echo $SHELL

 Depending on the output of this command, you will copy the associated setup script. The local version of the script can have a filename of your choosing.

 If using an csh shell (or varient such as tcsh), copy the setenv_GPI_sample.csh script to your home directory (``cp setenv_GPI_sample.csh ~/setenv_GPI_custom.csh``), or another suitable location if desired.
 
 If you are using an sh or bash shell, copy the setenv_GPI_sample.bash script to your home directory (``cp setenv_GPI_sample.bash ~/setenv_GPI_custom.bash``), or another suitable location if desired.

 The script file can be renamed as desired, for instance to have a leading . to make it a hidden file. 

 The next step is to ensure this script file is sourced automatically for each terminal session.

 **For bash shell users:**
  
  For users using a bash shell, modifications should be made to your .bash_profile (located in your home directory). Note that a typical install of the Mac OSX will not create the file by default. If you have not created a .bash_profile already, you must do so using your favourite text editor (note that the ``<.>`` in front of the filename means it will be hidden from standard ``ls`` commands, use ``ls -a`` to see all hidden files).
  
  Your script (e.g. setenv_GPI_custom.bash) should be sourced by inserting the following command into the .bash_profile:

  ``source ~/setenv_GPI_custom.bash``
  
  Save the script. Now each time you open a new terminal (or tab), the environment variables set above (e.g. GPI_RAW_DATA_DIR) should be set. The user should test this by typing the following command in a newly opened terminal:

  ``echo $GPI_RAW_DATA_DIR``

  If the command does not return the path you set in the script, then the .bash_profile is not being sourced, or you have an error in your script. See the :ref:`FAQ <frequently-asked-questions>` troubleshooting help.

 
 **For csh/tcsh users:**

  For users using a csh/tcsh shell, modifications should be made to your .cshrc or .tcshrc (located in your home directory). Note that a typical install of the Mac OSX will not create the file by default. If you have not created a .tcshrc (or .shrc .cshrc) already, you must do so using your favourite text editor (note that the ``<.>`` in front of the filename means it will be hidden from standard ``ls`` commands, use ``ls -a`` to see all hidden files).
  
  Your script (e.g. setenv_GPI_custom.csh) should be sourced by inserting the following command into the .tcshrc (or .shrc .cshrc) file: 

  ``source ~/setenv_GPI_custom.csh``
  
  Save the script. Now each time you open a new terminal (or tab), the environment variables set above (e.g. GPI_RAW_DATA_DIR) should be set. The user should test this by typing the following command in a newly opened terminal:

  ``echo $GPI_RAW_DATA_DIR``

  If the command does not return the path you set in the script, then the .tcshrc (or .shrc .cshrc) is not being sourced, or you have an error in your script. See the :ref:`FAQ <frequently-asked-questions>` troubleshooting help.

 Now proceed to the next section, :ref:`config-envvars`.

.. admonition:: Windows

    .. image:: icon_windows2.png

 If you **have IDL**, the best approach is to copy the sample code ``scripts\setenv_gpi_windows.pro`` to somewhere in your IDL path. Once completed, we will proceed to edit this file in the next section,  :ref:`config-envvars`.
 Environment variables can be set from within IDL, for instance, ::

   IDL> setenv,'GPI_DRP_QUEUE_DIR=E:\pipeline\drf_queue\'

 The setenv_gpi_windows.pro script uses this mechanism to set all the necessary paths. These commands must be repeated for each IDL session. You should `configure IDL to automatically run this program on startup <http://www.exelisvis.com/Support/HelpArticlesDetail/TabId/219/ArtMID/900/ArticleID/5367/How-do-I-specify-a-program-to-automatically-run-when-my-IDL-session-starts-up.aspx>`_.

 If you **do not have IDL** then environment variables can be set from the Control Panel's system settings dialog.  See `how to set environment variables in Windows <http://www.computerhope.com/issues/ch000549.htm>`_. 

 
 Using your method of choice, we will set the required environment variables in the next section, :ref:`config-envvars`.	   



.. _config-envvars:

Setting directory paths via environment variables
---------------------------------------------------
The following path variables are **required** to be defined.
Edit your shell configuration files (e.g. by editing the ``.gpienv`` file created by the automatic setup script, or editing the ``setenv_gpi_*`` templates discussed in the previous section)
to set the variables equal to your chosen installation paths. 


=====================  ====================================  ======================================
Variable                Contains                                Example
=====================  ====================================  ======================================
GPI_RAW_DATA_DIR        Default path for FITS file input        ``/home/username/gpi/rawdata``
GPI_REDUCED_DATA_DIR    Path to save output files               ``/home/username/gpi/reduced``
GPI_DRP_QUEUE_DIR       Path to queue directory                 ``/home/username/gpi/queue``
=====================  ====================================  ======================================

Note that the user must have write permissions to the ``$GPI_DRP_QUEUE_DIR`` and ``$GPI_REDUCED_DATA_DIR``. The raw data dir may be read-only.   


If you are running the **compiled** version of the pipeline, you must also set two additional environment variables
to indicate where you have installed the pipeline. This should be the directory path of the unzipped pipeline
download file.

=====================  ====================================  ================================================================
Variable                Contains                                Example
=====================  ====================================  ================================================================
IDL_DIR                Location of the IDL runtime library.  ``/home/username/gpi/gpi_pipeline_1.2.0/executables/idl/idl83``
GPI_DRP_DIR            Location of installed pipeline        ``/home/username/gpi/gpi_pipeline_1.2.0/``
=====================  ====================================  ================================================================



The following are paths are **optional** to define as environment variables. If not set explicitly, the pipeline will automatically use reasonable default values: 

======================  =======================================  ===========================================================
Variable                  Contains                                   Default Value if Not Set Explicitly
======================  =======================================  ===========================================================
GPI_DRP_DIR             Root dir of pipeline software             Determined automatically, location of
                                                                  the IDL pipeline code. Contains 
                                                                  subdirectories: backbone, config, 
                                                                  gpitv etc. (Optional for source code installs, required
                                                                  for compiled code installs.)
GPI_DRP_CONFIG_DIR      Path to directory containing pipeline    ``$GPI_DRP_DIR/config``
                        config files and ancillary data.           
GPI_DRP_TEMPLATES_DIR   Path to recipe templates                 ``$GPI_DRP_DIR/recipe_templates``
GPI_DRP_LOG_DIR         Path to save output log files             ``$GPI_REDUCED_DATA_DIR/logs``
GPI_CALIBRATIONS_DIR    Location of Calibration Files Database    ``$GPI_REDUCED_DATA_DIR/calibrations``
GPI_RECIPE_OUTPUT_DIR   Where to save user-created Recipes        ``$GPI_REDUCED_DATA_DIR/recipes``
======================  =======================================  ===========================================================


The required paths above must be set before you can proceed, and those that will be
written to (queue, reduced, calibrations, and log) must have write permissions
for the user running the pipeline. 

 
.. _config-textfiles:

Configuration text files
-----------------------------------

As noted above, the GPI pipeline config file system is similar to many other Unix programs;
there's a system-wide config file that sets default settings, and then each
user may optionally have a file in their home directory that overrides those
settings.  

The allowable settings are listed in an :ref:`Appendix <config_settings>`. Many users will not need to adjust any of these since
the default settings should be fine for most cases; such users may wish to skip this section. 

The system default settings are stored in the file
``$GPI_DRP_DIR/config/pipeline_settings.txt`` provided with the pipeline software. 

If you wish to adjust settings, you should do so by creating a user settings file in your home directory rather than modifying
the system defaults file directly. This way your customized settings will be preserved when upgrading to a new version of the pipeline. 
You can create a user settings file just by copying the system settings file to your home directory. The location of the user config file depends on the
operating system. 

.. admonition:: Mac OS and Linux

      .. image:: icon_mac2.png

      .. image:: icon_linux2.png


    The user config file must be named ``.gpi_pipeline_settings`` located in the user's home directory. (This will be a hidden "dotfile" as is typical.)

.. admonition:: Windows

      .. image:: icon_windows2.png

    The user config file must be called ``gpi_pipeline_settings.txt`` be in the user's home directory.

.. admonition:: Note for Subversion Users

  Users installing from the Subversion repository, if you wish to change pipeline settings, you **must** create a local user config file in your
  home directory. **Do not**  modify the system default configuration file ``config/pipeline_settings.txt``. If you do
  this, whenever you update your code from subversion it could overwrite your
  configuration (and vice versa your local changes could get propagated to other users accidentally). 


**Configuration file contents:** The config file has an extremely simple plain text file format. Each line of it is just::
  SETTING_NAME <tab> SETTING_VALUE

Settings names are case insensitive. Values are all returned as strings.  Boolean
parameters are entered as 0 or 1. 


If you leave the local user config file blank or nonexistent for a given setting, the default setting from the system config will be used.  


.. note:: 
  
    In addition to being set via environment variables, the above
    directory names (e.g. GPI_CALIBRATIONS_DIR) may also be set in the configuration files (/config/gpi_pipeline_settings.txt). 
    The environment variables, if set, have higher precedence and will override the config files.  
    For historical reasons, environment variables are the preferred way to set paths (they
    are convenient for use interactively in the shell, for instance you can
    ``cd $GPI_RAW_DATA_DIR``, etc.). But, if desired for some reason, it is possible
    to set paths using just the text config files. 
      
  
 


.. _config-ancillarydata:

Ancillary data files
-----------------------------------

A handful of data files are distributed with the pipeline
in a subdirectory ``config``.  In most cases, users
will not have any need to edit any of these. They are listed here for completeness only. 

For instance, there is a file containing the orbital elements of calibration
binaries, while another file describes the wavelengths of emission lines in
the wavelength calibration lamps at Gemini. These files are provided

* **pipeline_constants.txt**: This is a text file containing various constants about the GPI instrument, Gemini South, and so on. These values are not expected to change often, if ever. The format of this file is identical to the pipeline settings file.  A full list of constants and default values is available in the :ref:`Appendix <gpi_constants>`.

* **gpi_pipeline_primitives.xml**: This file is an index of all available pipeline primitives. It is 
  generated automatically by pipeline development scripts; see the Developer's Guide.

* **ifs_cooldown_history.txt**: This text file lists dates when the GPI IFS was warmed
  up for maintenance or other activities. It is used by the Calibration Database to
  help decide which calibration files are most appopriate for reducing a given set of science data
  (In general, calibration files from a different cooldown are probably not optimal.)

* **keywordconfig.txt**: This file lists the nominal header keywords in GPI-produced 
  FITS files, and whether they are expected to be found in the primary HDU or an 
  image extension HDU.

* **lampemissionlines.txt**: This is a list of xenon and argon emission line wavelengths
  used in spectral calibration.

* **orb6orbits.txt**: This is a list of calibration binary orbital parameters, taken from
  the Washington Double Star Catalog's list of suggested calibration binaries. It is used
  in astrometric calibration.

* **trans_16_15.dat**: This is a model of atmospheric transmission vs wavelength, used in some
  optional routines for calibrating telluric throughput.

* **xlocs.fits** and **ylocs.fits**: are lenslet X and Y pixel coordinate lists for the 
  mostly unsupported non-dispersed engineering mode.

* **apodizer_spec.txt**: Table of GPI apodizers and their empirically determined satellite spot flux ratios.

* **filters**: This subdirectory contains the measured transmission profiles for the five GPI IFS bandpass filters.

* **pickles**: This subdirectory contains data files comprising the `Stellar Spectral Flux Atlas Libray, from Pickles (1998) <http://www.stsci.edu/hst/observatory/crds/pickles_atlas.html>`_. 

* **planet_models**: This subdirectory contains 
  model planet atmosphere spectra from `Spiegel and Burrows (2011) <http://www.astro.princeton.edu/~burrows/warmstart/index.html>`_, binned to lower resolution to match the GPI IFS.


Continue to reading about :ref:`first-startup`.




