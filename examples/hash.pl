#!/usr/local/bin/perl

use Geo::WeatherNOAA;

print "WeatherNOAA.pm v.$WeatherNOAA::VERSION\n";

($date,$warnings,$forecast) = 
     process_city_zone('cameron','pa','','get');

print "As of $date,\n";

foreach $warning (@$warnings) {
	print "WARNING: $warning\n";
}
foreach $key (keys %$forecast) {
	print "$key: $forecast->{$key}\n\n";
}

