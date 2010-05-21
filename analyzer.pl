#!/usr/bin/perl -w

##############################################################################
# File   : analyzer.pl
# Author : Guillaume-Jean Herbiet  <guillaume.herbiet@uni.lu>
#
#
# Copyright (c) 2009 Guillaume-Jean Herbiet     (http://herbiet.gforge.uni.lu)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Guillaume-Jean Herbiet
# <guillaume.herbiet@uni.lu>
# University of Luxembourg
# 6, rue Richard Coudenhove-Kalergi
# L-1359 Luxembourg
##############################################################################
use strict;
use warnings;

#-----------------------------------------------------------------------------
# Load aditional packages
#
use Getopt::Long;           # To easily retrieve arguments from command-line
use Data::Dumper;           # To dump content of hashes and arrays in debug mode
use Statistics::Descriptive;
use Scalar::Util qw(looks_like_number);

#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Global variables
#

#
# Generic variables
#
my $VERSION = '0.1';
my $DEBUG   = 0;
my $VERBOSE = 0;
my $QUIET   = 0;
my $NUMARGS = scalar(@ARGV);
my @ARGS    = @ARGV;
my $COMMAND = `basename $0`;
chomp($COMMAND);
my %OPTIONS;

#
# Script specific variables
#
#my @networks;          # List of network source files
my $files_regex;        # Regex to select files to parse
my @metrics = ();       # List of metrics to analyze
my $logpath = "log";    # Input directory for the simulation results
my $outpath = "out";    # Output directory for the generated statistics
my $discriminant;       # Name of the discriminant used
my $d;                  # Index of the discriminant
my $time_based = 0;     # Generate time (or iteration) based statistics

my %metrics_functions = (
    # Community
    "Q"     => "Modularity",
    "WQ"    => "Weighted Modularity",
    "NMI"   => "Normalized Mutual Information",
    "C"     => "Number of communities",
    "S"     => "Maximum community size",
    "I"     => "Average iteration duration",
    "ST"    => "Simulation time",
    "N"     => "Number of iterations",
    # MST
    "O"     => "Number of token operations",
    "TO"    => "Total number of token operations",
    "T"     => "Number of subtrees",
    "TS"    => "Maximum tree size",
    "P"     => "Performance Ratio",
    "B"     => "Number of tree bridge links",
    "MNR"   => "Misplaced Nodes Ratio"
);

#
# Found algorithms
#
my %algorithms;

#
# Found statistics
#
my %results;

#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Get passed arguments and check for validity.
#
my $res = GetOptions(
    \%OPTIONS,
    'verbose|v+'        => \$VERBOSE,
    'help|h'            => sub { USAGE( exitval => 0 ); },
    'version'           => sub { VERSION_MESSAGE(); exit(0); },

    'files|f=s'         => \$files_regex,
    'metric|m=s'        => sub { set_metrics( $_[1] ) },
    'discriminant|d=s'  => sub { set_discriminant( $_[1] ) },
    'time|t+'           => \$time_based,
    
    'logpath|l=s'       => \$logpath,
    'outpath|o=s'       => \$outpath,
);

unless ( $res && ( scalar @metrics ) > 0 ) {
    print STDERR "Error in arguments.\n";
    USAGE( exitval => 1);
    exit 1;
}

#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Actual code
#

#
# Find all the files with the common file name in the out directory
#
verbose("Reading directory $logpath...");
opendir(DIR, $logpath) or die("Error in reading folder $logpath: $!\n");
my @files = grep(/$files_regex.*log$/, readdir(DIR));
closedir(DIR);
verbose("Found ".(scalar @files)." files matching \"$files_regex\"");
my $basename = $files_regex;
$basename =~ s/\W*//g;

#
# Generate the statistics
#
verbose("Generating statistics...");

FILE: foreach my $file (@files) {
    
    my $max_step = 0;

    #
    # Analyze the file name structure to find the discriminant value, the
    # algorithm name and the seed
    #
    my ($network, $algorithm, $seed) = split("_", $file);
    my $discriminant_value;
    if ($discriminant && $d) {
        my @parts = split("-", $network);
        die("Error: unable to identify $discriminant: index $d is too high") unless($parts[$d]);
        $discriminant_value = $parts[$d];
    }
    else {
        $discriminant_value = $basename;
        $discriminant = "network";
    }
    $algorithms{$algorithm} = 1;
    #verbose($discriminant_value);

    verbose("> Reading file $file.");
    open (IN, $logpath."/".$file)
        or die("Error in opening log file $logpath."/".$file: $!\n");
    
    #
    # This will store the partial results concerning this file
    #
    my %partial_results;
    my $max_steps;

    #
    # Read the log file
    #
    while (<IN>) {
        my $line = $_;
        
        #
        # Get values for each of the requested metrics
        #
        foreach my $m (@metrics) {
            #
            # Capture "non-standard" metrics
            #
            my $regex;
            if ($m eq "C" || $m eq "S") {
                #(3) D=17 58.8235294117647 24.3470616659322 62 21 100
                $regex = "^\\((\\d+)\\) D\\=(\\d+) (\\d+\\.?\\d*) (\\d+\\.?\\d*) (\\d+\\.?\\d*) (\\d+) (\\d+)";
            }
            elsif ($m eq "TS") {
                #(3) TD=17 58.8235294117647 24.3470616659322 62 21 100
                $regex = "^\\((\\d+)\\) TD\\=(\\d+) (\\d+\\.?\\d*) (\\d+\\.?\\d*) (\\d+\\.?\\d*) (\\d+) (\\d+)";
            }
            #
            # Capture "standard" metrics
            #
            else {
                # (0) NMI=0.743126621238971
                $regex = "^\\((\\d+)\\) $m\\=(\\-?\\d+\\.?\\d*)";
            }

            if ($line =~ /$regex/) {
                my $res;
                if ($m eq "S" || $m eq "TS") {
                    $res = $7;
                }
                # Correct Performance ratio computation
                #elsif ($m eq "P") {
                #    $res = 1 / $2;
                #}
                else {
                    $res = $2;
                }
                
                #
                # Save to the requested partial results
                #
                if ($time_based && !($m eq "ST") && !($m eq "TO")) {
                    $partial_results{$m}{time}[$1] = $res;
                }
                if (!exists($partial_results{$m}{max}) ||
                    ($m eq "C" && $partial_results{$m}{max} > $res) ||
                    $partial_results{$m}{max} < $res) {
                        $partial_results{$m}{max} = $res;
                }
            $max_steps = $1;
            }
        }
        
    }
    #
    # Number of iterations
    #
    if (grep(/^N$/, @metrics)) {
        $partial_results{N}{max} = $max_steps;
    }
    #verbose(Dumper(\%partial_results));
    close(IN);
    
    
    
    #
    # Now report the results to the generic results hash
    #
    foreach my $m (keys %partial_results) {
        #
        # Maximum values
        #
        unless(exists($results{$discriminant_value}{$algorithm}{$m}{max})) {
            $results{$discriminant_value}{$algorithm}{$m}{max} =
                Statistics::Descriptive::Full->new();
        }
        $results{$discriminant_value}{$algorithm}{$m}{max}
            ->add_data($partial_results{$m}{max});
            
        #
        # Time values
        #
        if ($time_based && exists($partial_results{$m}{time})) {
            for(my $i=0; $i<(scalar @{$partial_results{$m}{time}}); $i++) {
                
                unless(exists($results{$discriminant_value}{$algorithm}{$m}{time}[$i])) {
                    $results{$discriminant_value}{$algorithm}{$m}{time}[$i] =
                    Statistics::Descriptive::Full->new();
                }
                $results{$discriminant_value}{$algorithm}{$m}{time}[$i]
                    ->add_data($partial_results{$m}{time}[$i]);
            }
        }
    }
}
#verbose(Dumper(\%results));

#
# Generate the data files
#
verbose("Generating data files...");
foreach my $m (@metrics) {
    my $outfile;
    if ($discriminant eq "network") {
        $outfile = $outpath."/".$basename."_".$m.".dat";
    }
    else {
        $outfile = $outpath."/".$basename."_".$discriminant."_".$m.".dat";
    }
    
    verbose("> Generating $outfile");
    open (DAT, ">", $outfile) or
        die("Error in opening $outfile for writing: $!\n");
    
    my $header = 1;
    #
    # Sort the discriminants differently if they are numeric or not
    #
    my @results_keys = keys %results;
    if (looks_like_number($results_keys[0])) {
        @results_keys = sort {$a <=> $b} @results_keys;
    }
    else {
        @results_keys = @results_keys;
    }
    foreach my $d (@results_keys) {
        print DAT "# $discriminant" if ($header);
        my $str;
        foreach my $a (sort keys %{$results{$d}}) {
            if ($header) {
                print DAT " $a";
            }
            foreach my $f ("mean", "standard_deviation", "min", "max") {
                $str .= " ".$results{$d}{$a}{$m}{max}->$f();
            }
        }
        print DAT "\n$d $str";
        $header = 0 if ($header);
    }
    print DAT "\n";
    close(DAT);
}


#
# Generate the plot files
#
verbose("Generating gnuplot command files...");
foreach my $m (@metrics) {
    my $pltfile;
    my $outfile;
    my $datfile;
    if ($discriminant eq "network") {
        $pltfile = $outpath."/".$basename."_".$m.".plt";
        $outfile = $outpath."/".$basename."_".$m.".eps";
        $datfile = $outpath."/".$basename."_".$m.".dat";
    }
    else {
        $pltfile = $outpath."/".$basename."_".$discriminant."_".$m.".plt";
        $outfile = $outpath."/".$basename."_".$discriminant."_".$m.".eps";
        $datfile = $outpath."/".$basename."_".$discriminant."_".$m.".dat";
    }
    
    
    verbose("> Generating $pltfile");
    open (PLT, ">", $pltfile) or
        die("Error in opening $pltfile for writing: $!\n");
    
    my $key_position;
    if ($m eq "S") {
        $key_position = "bottom right";
    }
    else {
        $key_position = "top right";
    }

    print PLT <<EOF;
set title 'Evolution of $metrics_functions{$m} for test \"$basename\"'
set xlabel '$discriminant'
set ylabel '$metrics_functions{$m}'

set terminal postscript enhanced eps color "Times-Roman" 18
set output '$outfile'

set key $key_position
set grid

set style line 1 lt 1 lc rgb "orange" lw 4 pt 1
set style line 2 lt 4 lc rgb "orange" lw 2 pt 1
set style line 3 lt 1 lc rgb "red" lw 4 pt 3
set style line 4 lt 4 lc rgb "red" lw 2 pt 3
set style line 5 lt 1 lc rgb "blue" lw 4 pt 5
set style line 6 lt 4 lc rgb "blue" lw 2 pt 5
set style line 7 lt 1 lc rgb "violet" lw 4 pt 6
set style line 8 lt 4 lc rgb "violet" lw 2 pt 6
set style line 9 lt 1 lc rgb "green" lw 4 pt 9
set style line 10 lt 4 lc rgb "green" lw 2 pt 9

plot \\
EOF

    my $i=0;
    foreach my $a (sort keys %algorithms) {
        print PLT "\t'$datfile' using 1:".(4*$i+2)." with lines ls ".(2*$i+1)." notitle, \\\n";
        print PLT "\t'$datfile' using 1:".(4*$i+2).":(\$".(4*$i+3)."/2) with errorbars ls ".(2*$i+1)." title '$a', \\\n";
        print PLT "\t'$datfile' using 1:".(4*$i+4)." with lines ls ".(2*$i+2)." notitle, \\\n";
        print PLT "\t'$datfile' using 1:".(4*$i+5)." with lines ls ".(2*$i+2)." notitle";
        print PLT ", \\" if ($i+1 < (scalar keys %algorithms));
        print PLT "\n";
        $i++;
    }
    close(PLT);
}

exit(0) unless($time_based);

#
# Generate time-based data files
#
verbose("Generating time-based data files...");
foreach my $m (@metrics) {
    
    #
    # Skip metrics that don't support time-based results
    #
    next if ($m eq "ST" || $m eq "N" || $m eq "TO");
    
    #
    # For all other metrics:
    # create a separated time-based data file for each determinant value
    #
    foreach my $d (keys %results) {
        my $outfile;
        if ($discriminant eq "network") {
            $outfile = $outpath."/".$basename."_".$m.".dat";
        }
        else {
            $outfile = $outpath."/".$basename."_".$discriminant."-".$d."_".$m.".dat";
        }
        
        verbose("> Generating $outfile");
        open (DAT, ">", $outfile) or
            die("Error in opening $outfile for writing: $!\n");
        
        #
        # Get the maximum number of iterations on all algorithms for this metric
        #
        my $max_iter = 0;
        foreach my $a (sort keys %{$results{$d}}) {
            $max_iter = (scalar @{$results{$d}{$a}{$m}{time}})
                if ($max_iter < (scalar @{$results{$d}{$a}{$m}{time}}));
        }
        
        #
        # Print statistical data for each algorithms for each iteration
        #
        my $header = 1;
        for (my $i=0; $i<$max_iter; $i++) {
            print DAT "# $discriminant=$d" if ($header);
            my $str;
            foreach my $a (sort keys %{$results{$d}}) {
                if ($header) {
                    print DAT " $a";
                }
                foreach my $f ("mean", "standard_deviation", "min", "max") {
                    if (exists($results{$d}{$a}{$m}{time}[$i])){
                        $str .= " ".$results{$d}{$a}{$m}{time}[$i]->$f();
                    }
                    else {
                        $str .= " ?";
                    }
                }
            }
            print DAT "$i $str\n";
            $header = 0 if ($header);
        }
        close(DAT);
    }
}

#
# Generate the time-based plot files
#
verbose("Generating time-based gnuplot command files...");
foreach my $m (@metrics) {
    
    #
    # Skip metrics that don't support time-based results
    #
    next if ($m eq "ST" || $m eq "N" || $m eq "TO");
    
    #
    # For all other metrics:
    # create a separated time-based data file for each determinant value
    #
    foreach my $d (keys %results) {
    
        my $pltfile;
        my $outfile;
        my $datfile;
        if ($discriminant eq "network") {
            $pltfile = $outpath."/".$basename."_".$m.".plt";
            $outfile = $outpath."/".$basename."_".$m.".eps";
            $datfile = $outpath."/".$basename."_".$m.".dat";
        }
        else {
            $pltfile = $outpath."/".$basename."_".$discriminant."-".$d."_".$m.".plt";
            $outfile = $outpath."/".$basename."_".$discriminant."-".$d."_".$m.".eps";
            $datfile = $outpath."/".$basename."_".$discriminant."-".$d."_".$m.".dat";
        }
    
    
        verbose("> Generating $pltfile");
        open (PLT, ">", $pltfile) or
            die("Error in opening $pltfile for writing: $!\n");
    
        my $key_position;
        if ($m eq "S") {
            $key_position = "bottom right";
        }
        else {
            $key_position = "top right";
        }

        print PLT <<EOF;
set title 'Evolution of $metrics_functions{$m} for test \"$basename\"'
set xlabel 'iterations'
set ylabel '$metrics_functions{$m}'

set terminal postscript enhanced eps color "Times-Roman" 18
set output '$outfile'

set key $key_position
set grid

set style line 1 lt 1 lc rgb "orange" lw 4 pt 1
set style line 2 lt 4 lc rgb "orange" lw 2 pt 1
set style line 3 lt 1 lc rgb "red" lw 4 pt 3
set style line 4 lt 4 lc rgb "red" lw 2 pt 3
set style line 5 lt 1 lc rgb "blue" lw 4 pt 5
set style line 6 lt 4 lc rgb "blue" lw 2 pt 5
set style line 7 lt 1 lc rgb "violet" lw 4 pt 6
set style line 8 lt 4 lc rgb "violet" lw 2 pt 6
set style line 9 lt 1 lc rgb "green" lw 4 pt 9
set style line 10 lt 4 lc rgb "green" lw 2 pt 9

plot \\
EOF

        my $i=0;
        foreach my $a (sort keys %algorithms) {
            print PLT "\t'$datfile' using 1:".(4*$i+2)." with lines ls ".(2*$i+1)." notitle, \\\n";
            print PLT "\t'$datfile' using 1:".(4*$i+2).":(\$".(4*$i+3)."/2) with errorbars ls ".(2*$i+1)." title '$a', \\\n";
            print PLT "\t'$datfile' using 1:".(4*$i+4)." with lines ls ".(2*$i+2)." notitle, \\\n";
            print PLT "\t'$datfile' using 1:".(4*$i+5)." with lines ls ".(2*$i+2)." notitle";
            print PLT ", \\" if ($i+1 < (scalar keys %algorithms));
            print PLT "\n";
            $i++;
        }
        close(PLT);
    }
}

#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Additional functions
#

#
# Set the metrics
#
sub set_metrics {
    if ($_[0] eq "all") {
        push(@metrics, (keys %metrics_functions));
    }
    elsif ( !grep(/^$_[0]$/, @metrics) && exists($metrics_functions{$_[0]})) {
        push(@metrics, $_[0]);
    }
}

#
# Set the discriminant
#
sub set_discriminant {
    ($discriminant, $d) = split('\=', $_[0], 2);
    unless ($discriminant && $d) {
        print "Error in discriminant definition.\n";
        print "Please use \"-d discriminant_name=index\".";
        exit 1;
    }
}

#
# Usage function
#
sub USAGE {
    my %parameters = @_;
    
    my $exitval = exists($parameters{exitval}) ?
        $parameters{exitval} : 0;
    
    print <<EOF;
$COMMAND [-h|--help] [-v|--verbose] [--version]
    -f|--files files_regex [-d|--discriminant discriminant_name=index]
    [-t|--time] -m|--metric metric_name [-m|--metric metric_name ...]
    [-l|--logpath path_to_log_dir] [-o|--outpath path_to_out_dir]
    
    --help, -h          : Print this help, then exit
    --version           : Print the script version, then exit
    --verbose, -v       : Enable user information output to STDOUT

    --files, -f         : Regex defining the set of files to process.
    --metric, -m        : Metric to analyze. Repeat option for several metrics
                          or use "all" value to select all metrics at once.
    --discriminant, -d  : Define the name and the index of the discriminant
                          used to parse the results. Format should be
                          discriminant_name=index.
                          (Default: complete network name).
    --time, -t          : Generate time (or iteration) based results for all
                          selected metrics
    
    --logpath, -l       : path to read the log files from (Default: ./log)
    --outpath, -o       : path to save the generated data files (Default: ./out)
EOF
exit $exitval;
}


#
# Print script version
#
sub VERSION_MESSAGE {
    print <<EOF;
This is $COMMAND v$VERSION.
Copyright (c) 2010 Guillaume-Jean Herbiet  (http://herbiet.gforge.uni.lu)
This is free software; see the source for copying conditions. There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
EOF
}

#
# Verbose output
#
sub verbose {
    print $_[0]."\n" if ($VERBOSE > 0);
}
#-----------------------------------------------------------------------------