.. GPI DRP documentation master file, created by
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

.. _installation:


GPI Data Pipeline Installation & Configuration 
##################################################

This chapter describes how to install the GPI data pipeline and configure it. Some details of pipeline installation depend upon your operating system. In the following pages, 
OS-specific directions are indicated by the Windows, Macintosh (Apple), and Linux/Unix (Penguin) icons.
 

If you already have IDL, the quickest route is to :ref:`download the latest source ZIP file <installing-from-zips>`, unzip it into your ``$IDL_PATH``, and :ref:`configure your path settings <configuring>`.

If you encounter problems, please see the :ref:`Frequently Asked Questions <faq>`, and then consult the `Gemini Data Reduction Forum <http://drforum.gemini.edu>`_.


Contents
=============

.. comment: The first line of the following
   table of contents is intentionally a circular
   reference to this very file. That's intentional
   in order to get the TOC to include the subsections
   of this page, and is treated OK by Sphinx.
.. comment: No actually it doesn't work well - 
   breaks the internal next/prev linking functionality
   So, split it out as a separate page

.. toctree::
   :maxdepth: 2

   overview.rst
   install_from_zips.rst
   install_from_repos.rst
   install_compiled.rst
   relnotes.rst
   known_issues.rst
   configuration.rst
   startup.rst
   config_settings.rst
   constants.rst
   xdefaults.rst



.. comment
  Indices and tables
  ------------------
  * :ref:`genindex`
  * :ref:`modindex`
  * :ref:`search`


