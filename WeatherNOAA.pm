
# $Id: WeatherNOAA.pm,v 4.24 1999/02/09 20:25:57 msolomon Exp $

package Geo::WeatherNOAA;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use LWP::Simple;
use LWP::UserAgent;
use Tie::IxHash;
use Text::Wrap;

require Exporter;

@ISA = qw(Exporter);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	make_noaa_table

	print_forecast
	print_current

	get_city_zone
	process_city_zone

	get_city_hourly
	process_city_hourly
);

$VERSION = do { my @r = (q$Revision: 4.24 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
my $URL_BASE = 'http://iwin.nws.noaa.gov/iwin/';

use vars '$proxy_from_env';
$proxy_from_env = 0;

# Preloaded methods go here.

sub print_forecast {
	my ($city, $state, $filename, $fileopt, $UA) = @_;
	my $in = get_city_zone($city,$state,$filename,$fileopt,$UA);

	my $out;

	$out = "Geo::WeatherNOAA.pm v.$Geo::WeatherNOAA::VERSION\n";

	my ($date,$warnings,$forecast) = 
	   process_city_zone($city,$state,$filename,$fileopt);

	$out .= "As of $date:\n";
	foreach my $warning (@$warnings) {
		$out .= wrap('WARNING: ','    ',"$warning\n");
	}
	foreach my $key (keys %$forecast) {
        	$out .= wrap('','    ',"$key: $forecast->{$key}\n");
	}
	return $out
}


#########################################################################
#########################################################################
#
# Zone file processing
#
#########################################################################
#########################################################################
sub process_city_zone {
	my ($city, $state, $filename, $fileopt, $UA) = @_;
	my $in = get_city_zone($city,$state,$filename,$fileopt);

	# Return error if problem getting URL
	if ($in =~ /Error/) {
		my %error;
		my @null;
		$error{'Error'} = 'Error';
		$error{'Network Error'} = $in;
		return ('',\@null,\%error);
	}

	# Split coverage, date, and forecast
	#
	my ($coverage, $date, $forecast) = ($in =~ /(^.*?)\n	# Coverage
						    (\d.*?)\n	# Date
						    (.*)/sx);	# Entire Forecast
	
	# Format Coverage
	#
	$coverage =~ s/corrected//gi;		# Remove stat word
	$coverage =~ s/(\/|-|\.\.\.)/,/g;	# Turn weird punct to commas
	$coverage =~ s/,\s*$//;			# Remove last comma
	$coverage = ucfirst_words($coverage);	# Make caps correct
	
	# Format date (easy)
	#
	$date = format_date($date);

	# Vars for forecast
	#
	my %forecast;
	tie %forecast, "Tie::IxHash";
	my @warnings;

	# Iterate through forecast and assign warnings to list or pairs to hash
	#
	my $forecast_item;	# Used as place holder for line breaks of $value
	my $warnings_done = 0;	# Flag for warnings (Always at top of forcast)

	foreach my $line (split "\n",$forecast) {
		my ($key,$value);
		($key,$value) = ($line =~ /(.*?)\.\.\.(.*)/);

		if (! $value) {
			# If there's no value, this must be either a warning or
			# a continutation of value-data
			$key = $line;
		}
		next if ($key =~ /EXTENDED/);


		$warnings_done = 1 if ( ($key) && ($value) );
		#print "\n\nWARN_DONE: $warnings_done\n";

		if ($warnings_done) {
			if ( ($key =~ s/^\.//) && ($value) && ($key) ) {
				# Add VALUE to KEY (new key)
				$key =~ s/^\.//;
				$key = ucfirst_words($key);
				$forecast_item = $key;
				$forecast{$forecast_item} .= $value;
			}
			else {
				# Add KEY (with data) to OLD KEY (FORECAST_ITEM)
				$forecast{$forecast_item} .= ' ' . $key;
			}
		}
		elsif ( (!$key) && ($value) ) {
			$value = ucfirst lc $value;
			push @warnings, $value;
		}
	}

	foreach my $key ( keys %forecast ) {
		$forecast{$key} =~ tr/\n//d;			# Remove newlines
		#$forecast{$key} = lc($forecast{$key});	# No all CAPS
		$forecast{$key} =~ s/\s+/ /g;			# Rid of multi-spaces
		$forecast{$key} = sent_caps($forecast{$key});	# Proper sentance caps
	}

	return ($date,\@warnings,\%forecast);

} # process_city_zone()

sub get_city_zone {
	my ($city, $state, $filename, $fileopt, $UA) = @_;

	my $URL = $URL_BASE . lc $state . '/zone.html';
		

	# City and States must be capital
	#
	$state = uc($state);
	$city  = uc($city);

	# Declare some working vars
	#
	my ($rawData, $coverage);

	# Get data from filehandle object
	#
	$rawData = get_data($URL,$filename,$fileopt);

	# Return error if there's an error
	if ($rawData =~ /Error/) {
		return $rawData;
	}

	# Find our city's data from all raw data
	#
	foreach my $section ($rawData =~ /\n${state}Z.*?	# StateZone
					  \n(.*?)		# Data sect
					  \n(?:\$\$|NNN)/xsg) {
		# Iterate though section and get coverage
		my $coverage_ended = 0;
		foreach my $line (split /\n/, $section) {
			$line =~ tr/\r//d;
			$coverage .= $line . "\n" if (! $coverage_ended);
			if ($line !~ /^\w/) {
				$coverage_ended = 1;
			} 
		}
		return $section if ($coverage =~ /$city/i);
	}
	return "$city not found";
}

##############################################################################
##############################################################################
##
## Html for Mark's Site
## 
##############################################################################
##############################################################################

sub font2 {
	my $in = shift;
	my $font_face = $main::font_face || 'FACE="Helvetica, Lucida, Ariel"';
	return qq|<FONT SIZE="2" $font_face>$in</FONT>|;
}

sub make_noaa_table {
	my ($city, $state, $filename, $fileopt, $UA, $max_items) = @_;

	$fileopt ||= 'get';
	$max_items && $max_items--;
	$max_items ||= 3;
	
	my $med_bg   = $main::med_bg || '#ddddff';
	my $light_bg = $main::light_bg || '#eeeeff';
	my $font_face = $main::font_face || 'FACE="Helvetica, Lucida, Ariel"';

	my $locfilename;
	$locfilename = $filename . "_hourly";
	my $current = process_city_hourly( $city,$state,$locfilename,$fileopt,$UA );
		
	$locfilename = $filename . "_zone";
	my ($date,$warnings,$forecast) = process_city_zone( $city,$state,$locfilename,$fileopt,$UA);
	my $cols = (keys %$forecast);
	$cols = $max_items if $cols > $max_items;
	my $out;
	$out .= qq|<TABLE WIDTH="100%" CELLPADDING=1>\n|;
	$out .= qq|<!-- Current weather row -->\n|;
	$out .= qq|<TR VALIGN=TOP><TD BGCOLOR="$med_bg">\n|;
	$out .= font2('Current') . "\n</TD>\n";
	$out .= qq|<TD COLSPAN="$cols">|;
	$out .= font2($current) . "\n</TD></TR>\n";

	# Add one to make cols real width of table
	#
	$cols++;

	# Add warnings, if needed
	#
	if (@$warnings) {
		$out .= qq|<!-- Warnings -->\n|;
		foreach my $warning (@$warnings) {
			$out .= qq|<TR BGCOLOR="#FF8389" ALIGN="CENTER">\n|;
			$out .= qq|\t<TD COLSPAN="$cols">|;
			$out .= qq|<FONT $font_face COLOR="#440000">\n|;
			$out .= qq|\t$warning\n</TD></TR>\n|;
		}
	}

	# Iterate over the first $max_items items in forecast
	#
	my $bottom; # add this after the iteration;
	$out    .= qq|<TR VALIGN="TOP" BGCOLOR="$med_bg">\n|;
	$bottom .= qq|<TR VALIGN="TOP">\n|;
	foreach my $key ( (keys %$forecast)[0..($cols - 1)] ) {
		#print STDERR "DEBUG: $key\n";
		$out    .= "\t<TD>" . font2($key) . "</TD>\n";
		$bottom .= "\t<TD>" . font2($forecast->{$key}) . "</TD>\n";
	}
	$out .= "</TR>\n" . $bottom . "</TR>\n";
	
	# Add credits
	#
	my $wx_cred = '<A HREF="http://www.noaa.gov">NOAA</A> forecast made ' .
	  "$date by " .
	  "<A HREF=\"http://www.seva.net/~msolomon/WeatherNOAA/dist/\">" .
	  "Geo::WeatherNOAA</A> V.$Geo::WeatherNOAA::VERSION";
	$out .= qq|<TR BGCOLOR="$light_bg" ALIGN="CENTER">\n|;
	$out .= qq|<TD COLSPAN="$cols">| . font2($wx_cred) . "</TD></TR>\n";
	$out .= qq|</TABLE>\n|;



}

##############################################################################
##############################################################################
##
## Misc funcs
## 
##############################################################################
##############################################################################

sub get_url {
    my ($URL, $UA) = @_;

	$URL or die "No URL to get!";

    # Create the useragent and get the data
    #
    if (! $UA) {
	$UA = new LWP::UserAgent;
        $UA->env_proxy if $proxy_from_env;
    }
    $UA->agent("WeatherNOAA/$VERSION");
    
    # Create a request
    my $req = new HTTP::Request GET => $URL;
    my $res = $UA->request($req);
    if ($res->is_success) {	
		return $res->content;
    }
    else {
		return;
    }
} # getURL()    

sub get_data {
	my ($URL,$filename,$fileopt,$UA) = @_;

	$fileopt ||= 'get';

	my $data;	# Data

	if ( ($fileopt eq 'get') || ($fileopt eq 'save') ) {
		print STDERR "Retrieving $URL\n" if $main::opt_v;
		$data = get_url($URL,$UA) || 
			return "Error getting data from $URL"; 
		if ( $fileopt eq 'save' ) {
			print STDERR "Writing $URL to $filename\n" if $main::opt_v;
			open(OUT,">$filename") or die "Cannot create $filename";
			print OUT $data;
			close OUT;
			$fileopt = 'usefile';
		}
	}
	if ( $fileopt eq 'usefile' ) {
		print STDERR "Reading data from $filename\n" if $main::opt_v;
		open(FILE,$filename) or die "Cannot read $filename";
		while (<FILE>) { $data .= $_; }
	}
	return $data;
} # get_fh

sub format_date {
	my $in = shift;
	$in =~ s/^(\d+)(\d\d)\s(AM|PM)\s(\w+)\s(\w+)\s(\w+)\s0*(\d+)/$1:$2\L$3\E ($4) \u\L$5\E\E \u\L$6 $7,/;
	$in =~ tr/\r//d;
	return $in;
}
sub sent_caps {
	my $in = shift;
	$in = ucfirst(lc($in));
	$in =~ s/(\.\W+)(\w)/$1\U$2/g;		# Proper sentance caps
	return $in;
}

sub ucfirst_words {
	my ($in) = @_;
	return join " ", map ucfirst(lc($_)),(split /\s+/, $in);
}

#########################################################################
#########################################################################
##
## Hourly city data
##
#########################################################################
#########################################################################

sub get_city_hourly {
	my ($city,$state,$filename,$fileopt,$UA) = @_;
	
	# City and state in all caps please
	#
	$city  = uc $city;
	$state = uc $state;

	# work var
	my ($fields,$line,$date,$time);
	
	# Get data
	#
	my $URL = $URL_BASE . lc $state . '/hourly.html';
	my $data = get_data($URL,$filename,$fileopt,$UA);

	# Return error if there's an error
	if ($data =~ /Error/) {
		my %retHash;
		$retHash{ERROR} = $data;
		return \%retHash;
	}

	$data =~ s/\r//g;

	# Get line for our city from Data
	#
	foreach (split /\n/, $data) {
		chomp;
		$date   = $_ if /^\s*(\d+)(\d\d)\s+(AM|PM)\s+(\w+)/;
		$time = "$1:$2 $3" if (($1) && ($2) && ($3));
		$fields = $_ if /^CITY/;
		$line   = $_ if /^$city\s/;
		
		# Newest data seems to be at the top of the file
		last if $line;
	}
	$date = format_date($date);

	# unpack gives error of the string is smaller than the unpack string
	$line .= ' ' x (64 - length($line)) if length($line) < 64;
	
	return { } unless ( ($line) && ($fields) ); # Return ref to empty hash

	my @fields;
	push @fields, 'DATE', 'TIME', unpack
                '@0 A15 @15 A9 @24 A5 @29 A5 @35 A4 @39 A8 @47 A8 @55 A8', $fields if $fields;
	my @values;
	push @values, $date, $time, unpack 
		'@0 A15 @15 A9 @24 A5 @29 A5 @35 A4 @39 A8 @47 A8 @55 A8', $line;
	return { } if $values[3] eq 'NOT AVBL'; # Return ref to empty hash

	my %retValue;
	foreach my $i (0..$#fields) {
		$retValue{$fields[$i]} = $values[$i];
	}

	return \%retValue;

} # get_city_hourly()

sub print_current {
	my ($city,$state,$filename,$fileopt,$UA) = @_;
	my $in = process_city_hourly($city, $state, $filename, $fileopt,$UA);
	return wrap('','    ',$in)
}

	
sub process_city_hourly {
	my ($city,$state,$filename,$fileopt,$UA) = @_;
	my $in = get_city_hourly($city, $state, $filename, $fileopt,$UA);

	$state = uc($state);

	return $in->{ERROR} if $in->{ERROR};
	$in->{CITY} or return "No data available";
	$in->{CITY} = ucfirst_words($in->{CITY});
	
	my %sky = (
               'SUNNY'          => 'sunny skies',
               'MOSUNNY'        => 'mostly sunny skies',
               'PTSUNNY'        => 'partly sunny skies',
               'CLEAR'          => 'clear weather',
               'DRIZZLE'        => 'a drizzle',
               'CLOUDY'         => 'cloudy skies',
               'MOCLDY'         => 'mostly cloudy skies',
               'PTCLDY'         => 'partly cloudy skies',
               'LGT RAIN'       => 'light rain',
               'FLURRIES'       => 'flurries',
               'LGT SNOW'       => 'light snow',
               'SNOW'           => 'snow',
               'N/A'            => 'N/A',
               'NOT AVBL'       => '*not available*',
               'FAIR'           => 'fair weather');

	# Format the wind direction and speed
	#
	my %compass = qw/N north S south E east W west/;
	my $direction = join '',map $compass{$_},split(/(\w)\d/g, $in->{WIND});
	my ($speed) = ($in->{WIND} =~ /(\d+)/);
	my ($gusts) = ($in->{WIND} =~ /G(\d+)/);

	if ($in->{WIND} eq 'CALM') {
		$in->{WIND} = 'calm';
	}
	else {
		$in->{WIND} = "$direction at ${speed} mph";
		$in->{WIND} .= ", gusts up to ${gusts} mph" if $gusts;
	}

	# Format relative hudity and ibarometric pressure
	#
	my $rh_pres;
    	if ($in->{RH}) {
        	$rh_pres = " The relative humidity was $in->{RH}\%";
    	}
	if ($in->{PRES}) {
          my %rise_fall = qw/R rising S steady F falling/;
          my $direction = join '',map $rise_fall{$_},split(/\d(\w)/g, $in->{PRES});
          $in->{PRES} =~ tr/RSF//d;
          if ($rh_pres) {
                $rh_pres .= ", and b";
          }
          else {
                $rh_pres .= " B";
          }
          $rh_pres .= "arometric pressure was $direction from $in->{PRES} in";
    	}
    	$rh_pres .= '.' if $rh_pres;

	# Format output sentence
	#
	my $out;
	$out  = "At $in->{TIME}, $in->{CITY}, $state was experiencing ";
	$out .= $sky{$in->{'SKY/WX'}} . " ";
	$out .= "at $in->{TEMP}&deg;F, wind was $in->{WIND}. $rh_pres\n";
	return $out;

} # process_city_hourly()

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Geo::WeatherNOAA - Perl extension for interpreting the NOAA weather data

=head1 SYNOPSIS

  use Geo::WeatherNOAA;
  ($date,$warnings,$forecast) = 
     process_city_zone('newport','ri','','get');

  foreach $key (keys %$forecast) {
  	print "$key: $forecast->{$key}\n";
  }
  
  print process_city_hourly('newport news', 'va', '', 'get');

or

  use Geo::WeatherNOAA;
  print print_forecast('newport news','va');

=head1 DESCRIPTION

This module is intended to interpret the NOAA zone forecasts and current
city hourly data files.  It should give a programmer an easy time to use the
data instead of having to mine it.

=head1 REQUIRES

=over 4

=item * Tie::IxHash

=item * LWP::Simple

=item * LWP::UserAgent

=item * Text::Wrap

=back

=head1 FUNCTIONS

=over 4

=item * print_forecast(CITY,STATE,FILENAME,FILEOPT,LWP_UserAgent)

Returns text of the forecast

=item * print_current(CITY,STATE,FILENAME,FILEOPT,LWP_UserAgent)

Returns text of current weather

=item * make_noaa_table(CITY,STATE,FILENAME,FILEOPT,LWP_UserAgent, MaxItems)

This call gives the basic html table with current data and forecast for the
next four periods ("tonight", "tomorrow","tomorrow night","day after")
and warnings in an (I think) attractive, easy to read way.

Max Items is a way to limit the number of items in the table returned...
I think it looks best with no more than 4...5 gets crowded looking.

=item * process_city_hourly(CITY,STATE,FILENAME,FILEOPT,LWP_UserAgent)

FILENAME is the file read from with FILEOPT "usefile" and written to
if FILEOPT is "save"

FILEOPT can be one of the following

	- save
		will get and save the data to FILENAME
	- get
		will retrieve new data (not store it)
	- usefile
		will not retrieve data from URL, 
		use FILENAME for data

The fifth argument is for a user created LWP::UserAgent(3) which can
be configured to work with firewalls. See the LWP::UserAgent(3) manpage 
for specific instructions. A basic example is like this: 

   my $ua = new LWP::UserAgent;
   $ua->proxy(['http', 'ftp'], 'http://proxy.my.net:8080/');

If you merely wish to set your proxy data from environment 
variables (as in $ua-env_proxy>), simply set 

   $Geo::WeatherNOAA::proxy_from_env = 1;


=item * process_city_zone(CITY,STATE,FILENAME,FILEOPT,LWP_UserAgent)

Call CITY, STATE, FILENAME (explained above), FILEOPT(explained above),
and UserAgent (Explained above).

The return is a three element list containing a) a string of the date/time
of the forecast, b) a reference to the list of warnings (if any), and
c) a reference to the hash of forecast.  I recommend calling it like this:

    ($date, $warnings, $forecast) = 
        process_city_zone('newport news','va',
	'/tmp/va_zone.html', 'save');

Explanation of this call, it returns:

	$date
	- Scalar of the date of the forecast

	$warnings
	- Reference to the warnings list
	- EXAMPLE:
	  foreach (@$warnings) { print; }
	
	$forecast
	- Reference to the forecast KEY, VALUE pairs
	- EXAMPLE:
	  foreach $key (keys %$forecast) {
	  	print "$key: $forecast->{$key}\n";
	  }



=item * get_city_zone(CITY,STATE,FILENAME,FILEOPT,LWP_UserAgent)

This sub is to get the block of data from the data source, which is
chosen with the FILEOPTswitch.  

=item * get_city_hourly(CITY,STATE,FILENAME,FILEOPT,LWP_UserAgent)

This function gets the current weather from the data source, which is
decided from FILEOPT(explained above).  Input is CITY, STATE,
FILENAME (filename to read/write from if FILEOPTis "get" or "usefile"),
and UserAgent.

This function returns a reference to a hash containing the data. It

Same FILEOPTand LWP_UserAgent from above, and process the 
current weather data into an english sentence.

=back

=head1 AUTHOR

Mark Solomon

msolomon@seva.net

http://www.seva.net/~msolomon/

=head1 SEE ALSO

perl(1), Tie::IxHash(3), LWP::Simple(3), LWP::UserAgent(3).

=cut
