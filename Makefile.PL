
# $Id: Makefile.PL,v 1.2 1999/01/09 08:41:08 msolomon Exp $

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'WeatherNOAA',
    'VERSION_FROM' => 'WeatherNOAA.pm', # finds $VERSION
     'dist'      => {'COMPRESS'=>'gzip -9f', 'SUFFIX' => 'gz',
                         'ZIP'=>'zip','ZIPFLAGS'=>'-rl'},

);
