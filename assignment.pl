#!/usr/bin/perl -w

##############################################################################
# File   : assignment.pl
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
#use Data::Dumper;           # To dump content of hashes and arrays in debug mode
use Time::HiRes;            # High resoltion for time measurement
use Graph;                  # Graph management library

use Utils::Read;            # Read graphs from various formats
use Community::Algorithms;  # Community algorithms
use Community::Metrics;     # Community metrics
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Global variables
#

#
# Generic variables
#
my $VERSION = '0.2';
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
my @networks;           # List of network source files
my @seeds = (0);        # List of seeds used for RNG initialization
my @algos;              # List of algorithms to use
my $tree_algo;          # MST algorithm to use
my @metrics;            # List of metrics to compute
my $stability;          # Stability criterion to use
my $logpath = "log";    # Output directory for the simulation results
my $outpath = "out";    # Output directory for the other generated files
my @extra;              # List of extra arguments passed to the algorithm

my $rand_k;             # Average degree for random graphs
my $rand_N;             # Number of nodes for random graphs
my $rand_s;             # Seed for random graphs
my $ubigraph;           # Use Urbigraph for output
my $graphviz;           # Use GraphViz for output

my %metrics_functions = (
    # Community
    "Q"     => "modularity",
    "WQ"    => "weighted_modularity",
    "NMI"   => "nmi",
    "D"     => "distribution",
    "A"     => "assignment",
    # MST
    "O"     => "operations",
    "T"     => "subtrees",
    "TD"    => "trees_distribution",
    "P"     => "performance_ratio",
    "B"     => "tree_bridges",
    "MNR"   => "mnr"
);

#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Get passed arguments and check for validity.
#
my $res = GetOptions(
    \%OPTIONS,
    'verbose|v+'    => \$VERBOSE,
    #'quiet|q+'      => \$QUIET,
    #'debug|d'       => sub { $DEBUG = 1; $VERBOSE = 1; },
    #'help|h'       => sub { pod2usage( -exitval => 1, -verbose => 2 ); },
    'help|h'        => sub { USAGE( exitval => 0 ); },
    'version'       => sub { VERSION_MESSAGE(); exit(0); },

    'network|n=s'   => \@networks,
    'rand|r=s'      => sub { set_random( $_[1] ) },
    'algorithm|a=s' => sub { set_algos( $_[1] ) },
    'tree-algorithm|t=s' => \$tree_algo,
    'stability=s'   => \$stability,
    'metric|m=s'    => sub { set_metrics( $_[1] ) },
    'logpath|l=s'   => \$logpath,
    'outpath|o=s'   => \$outpath,
    'seed|s=s'      => sub { set_seeds( $_[1] ) },
    'extra|e=s'     => \@extra,
    'ubigraph|u+'   => \$ubigraph,
    'graphviz|g+'   => \$graphviz,
);

#pod2usage(-exitval => 1, -verbose => 2)
unless ( $res && ( scalar @networks ) > 0 && ( scalar @algos ) > 0 ) {
    print STDERR "Error in arguments.\n";
    USAGE( exitval => 1);
    exit 1;
}

# Add at least reference metric
if ( $tree_algo && defined(&{$tree_algo})) {
    set_metrics("P");
}
else {set_metrics("NMI");}

# Conditional package loading
if ($tree_algo) {require MST::Algorithms; import MST::Algorithms;}      # MST algorithms
if ($tree_algo) {require MST::Metrics; import MST::Metrics;}            # MST metrics
if ($stability) {require Utils::Stability; import Utils::Stability;}    # Stability metrics

if ($ubigraph)  {require Utils::Ubigraph; import Utils::Ubigraph;}  # Output to dynamic graph visualization software
if ($graphviz)  {require Utils::GraphViz; import Utils::GraphViz;}  # Output to snapshot graph visualization software

#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Simulation core code
#
foreach my $network (@networks) {
    
    #
    # Generate the original network (will be copied for each different configuration)
    # and get the maximum steps to execute (undef if static network)
    #
    my $G0;
    my $max_steps;
    my $network_name;

    #
    # Random network case
    #
    if ($rand_N) {
        verbose("Generating random network with parameters $rand_N, $rand_k, $network");

        my @nodes = (1..$rand_N);
        my $edges = $rand_k / $rand_N;

        $G0 = Graph::Undirected->new;
        $G0 = Graph->random_graph(
                    vertices => \@nodes,
                    edges_fill => $edges,
                    random_seed => $network);
        
        $network_name = "er-".$rand_N."-".$rand_k."-".$network;
    }
    #
    # File case
    #
    else {
        verbose("Generating network from input file $network.");
        ($G0, $max_steps, $network_name) = parse($network);
    }

    foreach my $algo (@algos) {
        
        verbose("> Executing algorithm $algo.");
        verbose("> Using parameters: ".join(" ", @extra)) if (scalar(@extra) > 0);
        
        #
        # Algorithm extra parameters
        #
        my %parameters;
        my $extra_string = set_extra_parameters(\%parameters, \@extra);
        $parameters{network_name} = $network_name;
        
        #
        # Trees generated by the algorithm and associated operations
        #
        my %trees;
        my $total_operations;

        foreach my $seed (@seeds) {
            
            verbose(">> Using seed $seed.");
            srand($seed);
            
            #
            # Set and open the logfile
            #
            $parameters{logfile} = $network_name."_";
            $parameters{logfile} .= $tree_algo."-" if ($tree_algo && defined(&{$tree_algo}));
            $parameters{logfile} .= $algo.$extra_string."_";
            $parameters{logfile} .= $seed;
            my $logfile = $logpath."/".$parameters{logfile}.".log";
            
            #
            # Skip if the logfile already exists
            #
            if (-f $logfile) {
                verbose(">> $logfile already exists, skipping this run.");
                next;
            }
            
            open (LOG, ">", $logfile) or
                die ("Error in opening logfile for writing $logfile: $!\n");
            verbose(">> Simulation will be saved to $logfile.");
            
            #
            # Remember the start time of this simulation
            #
            my $start = sprintf("%.9f", time);
            my $start_iter;
            my $end_iter;
            
            #
            # Create a deep copy (i.e. including attributes) of the original network
            # this is faster than reading the input file
            #
            my $G = $G0->deep_copy();
            print LOG "$network_name V=".($G->vertices())." E=".($G->edges())." $algo $seed\n";
            
            # Print the reference assignment if this metric is requested
            if (grep(/^A$/, @metrics)) {
                my @res = assignment($G, community_field => "value");
                print LOG "(-) A=".join(" ", @res)."\n";
            }
            
            #
            # First generate the Ubigraph object
            #
            my $UG;
            my $ug_edges;
            ($UG, $ug_edges) = ubigraph_create($G, %parameters) if ($ubigraph);
            
            #
            # Initialize the simulation at step 0
            #
            my $step = 0;
            
            #
            # Initialize the reference metric
            #
            my $prev_ref = 0;
            my $ref = 0;
            
            #
            # Execute algorithm until termination condition
            #
            while (!termination_condition($max_steps, $step, $prev_ref, $ref)) {
                
                #
                # Remember the begining of this iteration
                #
                $start_iter = sprintf("%.9f", time);
                
                #
                # Update some potentially required parameters for the algorithm
                #
                $parameters{step} = $step;
                #print "$step\n";
                verbose(">> Step $step.");
                
                #
                # Update the link weights if a particular stability
                # metric is chosen
                #
                if ($stability && defined(&{$stability})) {
                    no strict 'refs';
                    &{$stability}($G, %parameters);
                }
                
                #
                # Execute the chosen algorithm
                #
                no strict 'refs';
                &{$algo}($G, %parameters);
                
                #
                # Execute the chosen MST algorithm
                #
                if ( $tree_algo && defined(&{$tree_algo}) ) {
                    $parameters{dagrs_operations} = &{$tree_algo}($G, \%trees, %parameters);
                    $total_operations += $parameters{dagrs_operations};
                }
                
                #
                # Compute and print the requested metric
                #
                foreach my $m (@metrics) {
                    my @res;
                    if (grep(/^$m$/, qw(Q WQ NMI D A))) {
                        @res = &{$metrics_functions{$m}}($G, %parameters);
                    }
                    else {
                        @res = &{$metrics_functions{$m}}($G, \%trees, %parameters);
                    }
                    print LOG "($step) $m=".join(" ", @res)."\n";
                    
                    #
                    # Update reference metric
                    #
                    if ( ($tree_algo && defined(&{$tree_algo}) && $m eq "P") ||
                          $m eq "NMI") {
                        $prev_ref = $ref;
                        $ref = $res[0];
                    }
                }
                #
                # Remember the end of this iteration
                #
                $end_iter = sprintf("%.9f", time);
                print LOG "($step) I=".($end_iter-$start_iter)."\n";
                
                #
                # Update the graph if it is dynamic, or simply 
                # increment iteration for static graphs
                #
                if ($max_steps) {
                    ($G, $step, $network_name) = 
                    parse($network, graph => $G, step => $step);
                }
                else {$step++;}
                
                #
                # Update the Ubigraph object
                #
                if ($ubigraph) {
                    $parameters{ubigraph_edges} = $ug_edges;
                    ($UG, $ug_edges) = ubigraph_update($G, $UG, %parameters);
                }
                
                #
                # Generate a new GraphViz snapshot
                #
                if ($graphviz) {
                    graphviz_export($G, $outpath, %parameters);
                }

            }
            if ( $tree_algo && defined(&{$tree_algo}) ) {
                print LOG "(".($step-1).") TO=".($total_operations)."\n";
                
                my $mst_k = $G->MST_Kruskal;
                my $mst_p = $G->MST_Prim;
                my $mst_d = $G->MST_Dijkstra;

                print LOG "(".($step-1).") KMST=".(scalar $mst_k->edges)."\n";
                print LOG "(".($step-1).") PMST=".(scalar $mst_p->edges)."\n";
                print LOG "(".($step-1).") DMST=".(scalar $mst_d->edges)."\n";
            }
            print LOG "(".($step-1).") T=".($end_iter-$start)."\n";
            close(LOG);
        }
    }
}
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Additional functions
#

#
# Algorithm termination condition
#
sub termination_condition {
    my $max_steps = shift;
    my $step = shift;
    
    #
    # Dynamic networks
    #
    if ($max_steps) {
        #die ("Error: dynamic networks are not yet implemented.\n");
        #print "max steps = $max_steps, step = $step\n";
        return !($step <= $max_steps);
    }
    #
    # Static networks
    #
    else {
        my $prev_ref = shift;
        my $ref = shift;
        #
        # TODO: add max. time management and or maximum
        #
        #print "static termination condition\n";
        #print "ref=$ref, prev_ref=$prev_ref, step=$step\n";
        
        if ($tree_algo && defined(&{$tree_algo})) {
            return ($ref == 1 || $step > 1000);
        }
        else {
            return !(($step == 0 || $ref eq "-0" || abs($prev_ref - $ref) > 10**(-4) )
                    && $step <= 50);
        }
    }
}


#
# Set the seeds based on what the user submitted
#
sub set_seeds {
    @seeds = ();
    my ( $range, $step ) = split( '\+',   $_[0],  2 );
    my ( $start, $stop ) = split( '\.\.', $range, 2 );
    unless ($stop) {
        $stop = $start;
    }
    elsif ($stop < $start) {
        my $tmp = $start;
        $start = $stop;
        $stop = $tmp;
    }
    $step = 1 unless($step);
    for ( my $i = $start ; $i <= $stop ; $i += $step ) {
        push( @seeds, $i );
    }
}

#
# Set the algorithm
#
sub set_algos {
    if ( defined(&{$_[0]}) ) {
        push (@algos, $_[0]);
    }
}

#
# Set the metrics
#
sub set_metrics {
    if ( !grep(/^$_[0]$/, @metrics) &&
         exists($metrics_functions{$_[0]}) &&
         defined(&{$metrics_functions{$_[0]}}) ) {
        push(@metrics, $_[0]);
    }
}

#
# Set extra parameters
#
sub set_extra_parameters {
    my $parameters_ref = shift;
    my $extra_ref = shift;
    
    my %extras;
    my %short_extras;
    
    foreach my $e (@{$extra_ref}) {
        my ($key, $val) = split('\=', $e, 2);
        $val = "0.0" if (defined($val) && $val eq "0");
        $val = 1 unless ($val);
        $parameters_ref->{$key} = $val;
        $extras{$key} = $val;
    }
    
    # Generate shorter version of the extra parameters hash for the
    # output string
    foreach my $key (sort keys %extras) {
        my $len = 3;
        while (exists($short_extras{substr($key, 0, $len)})) {
            $len++;
        }
        $short_extras{substr($key, 0, $len)} = $extras{$key};
    }
    
    my $str = "";
    foreach my $k (sort keys %short_extras) {
        $str .= "-".$k."(".$short_extras{$k}.")";
    }
    return $str;
}

#
# Set random graph
#
sub set_random {
    ($rand_N, $rand_k, $rand_s) = split(',', $_[0], 3);
    unless ($rand_N && $rand_k && $rand_s) {
        print "Error in random network definition.\n";
        print "Please use \"-r nodes,edge_proba,runs\".";
        exit 1;
    }
    else {
        @networks = (0..($rand_s-1));
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
    (-n|--network network_file [-n|--network network_file_2 ...] | -r|--rand N,k,s)
    -a|--algorithm algorithm_name [-a|--algorithm algorithm_name ...]
    [-e|--extra parameter[=value] [-e|--extra parameter[=value] ...]]
    [--stability criterion] [-m|--metrics MET [-m|--metrics MET ...]]
    [-l|--logpath path_to_log_dir] [-o|--outpath path_to_out_dir]
    [-s|--seed n|n..m|n..m+k] [-u|--ubigraph] [-g|--graphviz]
    
    --help, -h          : Print this help, then exit
    --version           : Print the script version, then exit
    --verbose, -v       : Enable user information output to STDOUT

    --network, -n       : Path to network description file. The kind of the
                          network file is guessed and properly interpreted.
                          Repeat option for several network files.
    --rand, -r          : Generate n Erdös-Rényi undirected random graphs with
                          N nodes, and average degree of k.
                          The agrument for should be "-r N,k,s"
                          NOTE: when this option is active, any -n options
                          are not parsed.
    --algorithm, -a     : Name of the algorithm to execute. Repeat option
                          for several algorithms.
    --tree-algorithm, -t: Name of the minimum spanning tree algorithm to
                          execute. 
    --extra, -e         : Extra algorithm parameters. Can be of the form
                          i)   parameter: set parameter to 1 (true)
                          ii)  parameter=value: set parameter to value
                          Repeat option multiple times to define several extra
                          parameters. When same parameter is given multiple times,
                          only the last entry is meaningful.
    --stability         : Stability criterion to use as link weight in weighted
                          networks. This is updated at each iteration step
    --metric, -m        : Metric used to evaluate the algorithm. Repeat option
                          for several metrics.
                          Available metrics: D (distribution), Q (modularity),
                          WQ (weighted modularity), NMI (normalized mutual information),
                          D (community size distribution), A (complete assignment).
    --logpath, -l       : path to save the generated log file (Default: ./log)
    --outpath, -o       : path to save the generated output file (Default: ./out)
    --seed, -s          : Value(s) of the seed used to initialize the random
                          number generators. Can be of three forms :
                          i)   n: number "n" is used
                          ii)  n..m: all numbers between n and m (included)
                               are used (leading to m-n simulations)
                          iii) n..m+k : all numbers starting at n, incremented
                               by k and lesser or equal to m are used
    --ubigraph, -u      : Use UbiGraph for dynamic 3D visualization of
                          assignment process
    --graphviz, -g      : Use tge GraphViz program to generate one graph
                          snapshot per iteration.
                               
    NOTE: if N networks, A algorithms and S seeds are specified, then the
    script will be executed once for all the N*A*S unique configurations.
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
