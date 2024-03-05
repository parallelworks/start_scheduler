#!/bin/perl

############################################
#
#	LMstatparse 1.0 (c) ARM Ltd 2005.
#	Script to parse license tools log file
#
#	Written by David Scanlan for ARM
#	Last updated 19/09/2005
#
#	Usage:
#	--interval 						: interval between each call in seconds
#	--(lowdetail|highdetail)		: set the output detail
#	-f (all|feature1,feature2...)	: features to include
#	-c (port@host)					: specify license server
#	-p (path_to_lmtuil)				: specify lmutil path
#
############################################

use strict;
use threads;
use threads::shared;
use Getopt::Long;
use constant LOWDETAIL => '1';
use constant HIGHDETAIL => '2';
use constant DEFAULTINTERVAL => '10';

our($interval);						# user defined interval (seconds)
our($licserver);					# user specified license server (port@host)
our($lmutilpath);					# user specified path for lmutil
our($detail);						# user defined level of detail
our$folder = "licenses";		# name of folder (created from timestamp)
our($feature);						# store feature currently being worked on
our(%toolandlicversions) = ();		# array to hold which tools have which licenses
our($all);							# set to true (1) if all feature were selected
our($selected);						# set to true (1) if current feature has been selected
our(@chosenfeature);				# araay to hold a list of the chosen features
our($argument1);					# '-a' or '-f' dependent on a single feature chosen
our($argument2);					# only set for a single feature chosen
our($argument3);					# '-c' specifies license server
our($exitflag) : shared;			# exit flag set by thread to tell main loop to end
our(@logfilename);					# array used to hold output from lmutil lmstat

# take some arguments from the command line
GetOptions ('interval=i' => \$interval,
			'lowdetail' => sub { $detail = LOWDETAIL },
			'highdetail' => sub { $detail = HIGHDETAIL },
			'c=s' => \$licserver,
			'f=s' => \@chosenfeature,
			'p=s' => \$lmutilpath);
@chosenfeature = split(/,/,join(',',@chosenfeature));	# allow multiple features to be selected

# set some defaults if variables not specified
if (!$lmutilpath)
{
	$lmutilpath = "gtlmutil";		# use default path to lmutil
}
elsif ($lmutilpath =~ s/\.exe$//)	# try and catch some common cases
{
}
elsif ($lmutilpath =~ s/\\$/\\lmutil/)
{
}
elsif ($lmutilpath =~ s/\/$/\/lmutil/)
{
}
else
{
	$lmutilpath =~ s/(.*)/$1\/lmutil/;
}
if ($lmutilpath eq "lmutil")
{
	#print("Using default path for lmutil\n");
}
else
{
	#print("Using path: $lmutilpath\n");
}

if (!$licserver)
{
	$licserver = $ENV{GTISOFT_LICENSE_FILE};		# look here if not on command line
	if (!$licserver)
	{
		$licserver = $ENV{GTISOFT_LICENSE_FILE};		# second look here
		#print("Using ARMLMD_LICENSE_FILE\n");
	}
	else
	{
		#print("Using GTISOFT_LICENSE_FILE\n");
	}
}
else
{
	if ($licserver =~ m/^\d+@(\w+|-)+$/)		# check format of <port@host>
	{
	}
	else
	{
		#print("Wrong format for server, please use <port\@host>\n");
		exit();
	}
}
if (!$licserver)
{
	print("Could not find license server...\n");
	print("Please specify one using -c <port\@host>\n");
	exit();
}
else
{
	#print("Using $licserver\n");
	$argument3 = "-c $licserver";
}

if (!$interval)
{
	$interval = DEFAULTINTERVAL;
	#print("No interval given, default ".DEFAULTINTERVAL." seconds being used\n");
}

if (!$detail)
{
	$detail = LOWDETAIL;
	#print("No detail level given, default low detail being used\n");
}

if (scalar(@chosenfeature) == 0)
{
	push(@chosenfeature,"compiler");
	#print("No selected features given, default compiler being used\n");
}

# loop through chosen features
foreach(@chosenfeature)
{
	my$chosenfeature = $_;
	$chosenfeature = lc($chosenfeature);	# put all features in lower case in array
	if($chosenfeature eq "all")				# check if all is specified as one of the features
	{
		$all = 1;
	}
}

# echo back selected options or defaults
#print("Interval: $interval\nDetail: $detail\n");
#print("Features chosen:");
if ($all == 1)
{
	#print(" ALL\n");
	$argument1 = "-a";
}
else
{
	if (scalar @chosenfeature == 1)		# only one element in array (not 'all')
	{
		$argument1 = "-f";		# only one feature selected so "lmutil lmstat -f ..." can be used
		$argument2 = @chosenfeature[0];
	}
	else
	{
		$argument1 = "-a";
	}
	#print("\n");
	#foreach (@chosenfeature)
	#{
		#print("- $_\n");
	#}
}

# thread waiting for user to quit program
#my$thr = threads->create("EndProgram");
#print("Type 'x' and hit enter to exit\n");
# loop forever
our$timestamp = &GetTimeStamp();	# no arg for correct timestamp format for file
my($licvers) = 0;

@logfilename = `$lmutilpath lmstat $argument1 $argument2 $argument3`;
foreach my$line (@logfilename)
{
	if ($line =~ m/^Users of (\w+|_): +\(Total of (\d+) license\w* issued; +Total of (\d+) license\w* in use\)/)
	{
		# could only detect end of section by start of next feature details
		if ($detail > LOWDETAIL)
		{
			if (($feature) && (($selected == 1) || ($all == 1)))
			{
				# function to print extra detail about tool and license versions
				#&PrintDetailsToFile($feature,%toolandlicversions);
			}
		}
	 	%toolandlicversions = ();
		# only overwrite feature now extra details have been written
		$feature = $1;
		my($issued) = $2;
		my($inuse) = $3;
		$selected = 0;

		# set flag if feature was chosen at command line
		foreach (@chosenfeature)
		{
			my($feat)=$_;
			if ($feat eq $feature)
			{
				$selected = 1;
			}
		}

		# only do if the feature was selected at command line
		if (($selected == 1) || ($all == 1))
		{
			# no check if file exists without header
			if (!-e "./$folder/$feature.log")
			{
				my(%licfeature) = ();
				my(%licenses) = ();
				if (!%licenses)
				{
					%licenses = &GetNumOfLicsAll;
				}
				my(@ListOfKeys) = keys(%licenses);
				my($vers);
				foreach $vers (@ListOfKeys)
				{
					if ($vers =~ m/^($feature) (\d+.\d+)/)
					{
						my($versoffeature) = $2;
						$licfeature{$versoffeature} = $licenses{$vers};
					}
				}
				#&WriteHeader($feature,$interval,$detail,%licfeature);
			}
			&OneLineSummary($timestamp,$feature,$issued,$inuse);
		}
	}
	elsif ($line =~ m/\"($feature)\" v(\d+.\d+)/)
    {
	    $licvers = $2;
    }
	elsif ($line =~ m/\w+ \S+ \S+ \(v(\d+.\d+)\) \(\S+\/\d+ \d+\), start/)
	{
		my($toolvers) = $1;
		($toolandlicversions{"$feature License Vers: $licvers Tool Vers: $toolvers"}) += 1;			# increment count for a single vers of tools
	}
	elsif ($line =~ m/\w+ \S+ \S+ \(v(\d+.\d+)\) \(\S+\/\d+ \d+\) queued for (\d+)/)
	{
		my($toolvers) = $1;
		my($needed) = $2;
		($toolandlicversions{"queued for $feature License Vers: $licvers Tool Vers: $toolvers"}) += $needed;			# increment count for a queued licenses
	}
}

@logfilename=();



# subroutine used soley in LOWDETAIL mode and as a basis for HIGHDETAIL
# displays total tool licenses and how many are currently taken
sub OneLineSummary
{
	my($timestamp) = $_[0];
	my($feature) = $_[1];
	my($issued) = $_[2];
	my($inuse) = $_[3];
	my($filename) = $feature . ".log";
	#open( WORKINGFILE, ">./$folder/$filename" ) or die "Can't open $filename : $!";
	print ("$feature $inuse $issued");
	#close WORKINGFILE;
}


# extract license info from lic file
# should be ran once if no header for a file
sub GetNumOfLicsAll
{
	my@licensefile = `$lmutilpath lmstat -i $argument2 $argument3`;
	my(%versions) = ();
	foreach my$line (@licensefile)
	{
		#looking for "armasm 2.2 10	05-nov-2005	armlmd" for example
		if ($line =~ m/^(\w+|_)\s+(\d+.\d+)\s+(\d+)\s+/)
		{
			my($feature) = $1;
			my($vers) = $2;
			my($numoflics) = $3;
			$versions{"$feature $vers"} = "$numoflics";
		}
	}
	return(%versions);
}

# subroutine to print HIGHLEVEL detail to the output files
# takes feature name and an array of how many users are using which licenses with which version of the feature
# from this calculates total number of which version licenses taken
sub PrintDetailsToFile
{
	(my($feature),my($toolandlicversions)) = @_;
	my($filename) = $feature . ".log";
	open( WORKINGFILE, ">>./$folder/$filename" ) or die "Can't open $filename : $!";

	# lists full details of which version tools are using which version licenses
	my(%totallicversions) = ();
	my(@ListOfKeys) = sort(keys(%toolandlicversions));
	my($key1);
	foreach $key1 (@ListOfKeys)
	{
		if ($key1 =~ m/^$feature License Vers: (\d+.\d+)/)
		{
			$totallicversions{"$1"} = $totallicversions{$1} + $toolandlicversions{$key1};
		}
		print WORKINGFILE "- $toolandlicversions{$key1} x $key1\n";
	}

	# total number of license versions taken
	my(@ListOfKeys2) = sort(keys(%totallicversions));
	my($key2);
	foreach $key2 (@ListOfKeys2)
	{
		print WORKINGFILE ("- $totallicversions{$key2} v$key2 licenses taken\n");
	}

	close WORKINGFILE;

	%toolandlicversions = ();
	%totallicversions = ();
}


# subroutine to write the header at the start of each produced file
# takes which feature, what the interval is set to and an array of which versions/how many licenses are available for each
sub WriteHeader
{
	(my($feature),my($interval),my($detail),my(%licfeature)) = @_;
	my($filename) = $feature . ".log";

	if (!-d "$folder")		# check directory exists
	{
		mkdir($folder) or die "Can't create folder : $folder";
	}

	open( WORKINGFILE, ">>./$folder/$filename" ) or die "Can't open $filename : $!";
	print WORKINGFILE ("\$feature\t$feature\n");
	print WORKINGFILE ("\$interval\t$interval\n");
	my(@ListOfKeys) = keys(%licfeature);
	foreach (@ListOfKeys)
	{
		print WORKINGFILE ("\$seats\t\t$_\t\t$licfeature{$_}\n");
	}
	print WORKINGFILE ("\$detail\t$detail\n");
	close(WORKINGFILE);
}

# subroutine to get current time/date and return it in various formats
# takes no arguments
sub GetTimeStamp
{
	(my($second), my($minute), my($hour), my($day), my($month), my($year)) = localtime(time);
	if($second < 10)
	{
		$second = "0" . $second;
	}
	if($minute < 10)
	{
		$minute = "0" . $minute;
	}
	if($hour < 10)
	{
		$hour = "0" . $hour;
	}
	if($day < 10)
	{
		$day = "0" . $day;
	}
	$month = $month + 1;		# month fix
	if($month < 10)
	{
		$month = "0" . $month;
	}
	$year = $year + 1900;		# year fix

	my($timestamp) = 0;
	if($_[0] == 1)			# format for folder names
	{
		$timestamp = ($hour . $minute . $second . "_" . $day . $month . $year);
	}
	else					# format used for timestamp within file
	{
		$timestamp = ("$hour:$minute:$second $day\/$month\/$year");
	}
	return($timestamp);
}

# Thread to exit the program
# Currently could take a maximum of <interval> before exiting.
sub EndProgram
{
	my$pressedkey = getc();
    if ($pressedkey eq 'x')
    {
	    exit();
    }
}