##############################################################################
# File   : Utils/Read.pm
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
package Utils::Read;

use strict;
use warnings;
use base 'Exporter';

use Graph;              # Graph management library
use File::Basename;     # File name and path management


our $VERSION = '0.1';
our @EXPORT  = qw(parse parse_gml parse_lfr parse_dgs);

#
# Determines the file type then parse it with the appropriate function
#
sub parse {
    my $file = shift;
    my %parameters = @_;
    
    my @suffixes = ( ".gml" , ".dgs");
    my ($filename, $directories, $suffix) = fileparse($file, @suffixes);
    
    if ($suffix eq ".gml") {
        return (parse_gml($file, %parameters), undef, $filename);
    }
    elsif ($suffix eq ".dgs") {
        return (parse_dgs($file, %parameters), $filename);
    }
    elsif (-f $file."_network.dat" && -f $file."_community.dat") {
        return (parse_lfr($file, %parameters), undef, $filename);
    }
    else {
        die ("Error: unable to determine network file type $file for parsing.\n");
    }
}


#
# Parse a GML file and create a new undirected graph
# The code is based on the CLAIRlib GML parsing function
# see http://clair.si.umich.edu/clair/clairlib/pdoc/Network/Reader/GML.html#CODE1
#
sub parse_gml {
    my $file    = shift;
    my %parameters = @_;

    #
    # Create a graph, undirected by default, directed if requested by
    # the user.
    #
    my $G;
    if (exists($parameters{directed})) {
        $G = Graph->new( directed => 1 );
    }
    else {
        $G = Graph->new( undirected => 1 );
    }
    
    #
    # The graph is weighted (based on the "value" attribute of edges in the
    # GML file) by default, unweighted if requested bu the user.
    #
    my $ignoreweights = exists($parameters{unweighted});

    #
    # Read the GML file and capture meaningful lines.
    #
    open( GML, "<", $file ) or die ("Error in opening GML file $file for reading: $!\n");
    my @lines;
    my $l;
    my $id0Flag = 0;
    while ( $l = <GML> ) {
        $l =~ s/^\s+|\s+$//g;
        $l =~ s/\[|\]//g;
        $l =~ s/^\s+|\s+$//g;
        chomp $l;
        if ( $l =~ /^node|edge|id|label|source|target|value/ ) {
            if ( $l =~ /id 0/ ) {
                $id0Flag = 1;
            }
            push @lines, $l;
            #print $l. "\n";
        }
    }
    close GML;

    #
    # Create the nodes and their attributes.
    # TODO: manage overlapping communities
    #
    my $i;
    my ( $id, $label, $value, $source, $target );
    for ( $i = 0 ; $i <= $#lines ; $i++ ) {
        if ( $lines[$i] eq "node" && $i < $#lines ) {
            $id    = "undef";
            $label = "undef";
            $value = "undef";
            if ( $lines[ $i + 1 ] =~ /^id\s*(.*)/ ) {
                $id = $1;
                if ($id0Flag) {
                    $id++;
                }    # Matlab,Pajek can't handle nodes id'ed with 0
                $i++;
            }
            if ( $i + 1 < $#lines ) {
                if ( $lines[ $i + 1 ] =~ /^label\s*(.*)/ ) {
                    $label = $1;
                    $label =~ s/^\"+|\"+$//g;
                    $i++;
                }
                if ( $lines[ $i + 1 ] =~ /^value\s*(.*)/ ) {
                    $value = $1;
                    $value =~ s/^\"+|\"+$//g;
                    $i++;
                }
            }
            if ( $id ne "undef" ) {
                #print "Found node in File: id = $id";
                if ( $G->has_vertex($id) ) {
                    #print "  node already exists.\n";
                }
                else {
                    $G->add_vertex($id);
                    if ( $label ne "undef" ) {
                        #print "  Label = $label";
                    }
                    else {
                        $label = "N$id";
                    }
                    $G->set_vertex_attribute( $id, "label", $label );
                    if ( $value ne "undef" ) {
                        #print "  Value = $value";
                        $G->set_vertex_attribute( $id, "value", $value );
                    }
                    #print "\n";
                }
            }
        }

        #
        # Create the edges and their attributes (weight)
        #
        if ( $lines[$i] eq "edge" && $i < $#lines - 1 ) {
            $source = "undef";
            $target = "undef";
            $value  = "undef";
            if ( $lines[ $i + 1 ] =~ /^source\s*(.*)/ ) {
                $source = $1;
                if ($id0Flag) {
                    $source++;
                }
                $i++;
            }
            if ( $lines[ $i + 1 ] =~ /^target\s*(.*)/ ) {
                $target = $1;
                if ($id0Flag) {
                    $target++;
                }
                $i++;
            }
            if ( $i + 1 <= $#lines ) {
                if ( $lines[ $i + 1 ] =~ /^value\s*(.*)/ ) {
                    $value = $1;
                    $i++;
                }
            }
            if ($ignoreweights) {
                $value = 1;
            }
            if ( $source ne "undef" && $target ne "undef" ) {

                #print "Found edge from $source to $target";
                if ( !$G->has_vertex($source) ) {
                    #print "   Added node $source.";
                    $G->add_vertex( $source, label => "N$source" );
                }
                if ( !$G->has_vertex($target) ) {
                    #print "   Added node $target.";
                    $G->add_vertex( $target, label => "N$target" );
                }
                if ( !$G->has_edge( $source, $target ) ) {
                    if ( $value ne "undef" ) {
                        #print "  Value $value";
                        $G->add_weighted_edge( $source, $target, $value );
                    }
                    else {
                        $G->add_weighted_edge( $source, $target, 1 );
                    }
                    $G->set_edge_attribute($source, $target, "ae", 0);
                }
                else {
                    if ( $value ne "undef" ) {
                        #print "  Value = $value.  Added new weight to existing weight.";
                        $G->add_weighted_edge( $source, $target, $value );
                        $G->set_edge_attribute($source, $target, "ae", 0);
                    }
                }
                #print "\n";
            }
        }
    }
    return $G
}

#
# Parse a set of network definition files from the LFR test generator
#
sub parse_lfr {
    my $prefix = shift;
    my %parameters = @_;
    
    #
    # Create a graph, undirected by default, directed if requested by
    # the user.
    #
    my $G;
    if (exists($parameters{directed})) {
        $G = Graph->new( directed => 1 );
    }
    else {
        $G = Graph->new( undirected => 1 );
    }
    
    #
    # The graph is weighted (based on the "value" attribute of edges in the
    # GML file) by default, unweighted if requested bu the user.
    #
    my $ignoreweights = exists($parameters{unweighted});
    
    #
    # The NET file gives the list of edges, so we have to create both vertices
    # and edges at the same time
    #
    open ( NET, "<", $prefix."_network.dat")
        or die ("Error in opening network file ".$prefix."_network.dat for reading: $!\n");
    while ( <NET> ) {
        if ( /^(\d+)\s(\d+)\s?(\d+\.?\d*)?$/ ) {
            #print "Found edge from $1 to $2";
            if ( !$G->has_vertex($1) ) {
                #print "   Added node $1.";
                $G->add_vertex( $1);
                $G->set_vertex_attribute( $1, "label", "N$1" );
            }
            if ( !$G->has_vertex($2) ) {
                #print "   Added node $2.";
                $G->add_vertex( $2);
                $G->set_vertex_attribute( $2, "label", "N$2" );
            }
            
            if ( $3 && !$ignoreweights ) {
                $G->add_weighted_edge( $1, $2, $3 );
                #print " Weight set to $3";
            }
            else {
                $G->add_weighted_edge( $1, $2, 1 );
                #print " Weight set to 1";
            }
            $G->set_edge_attribute($1, $2, "ae", 0);
            #print "\n";
        }
    }
    close (NET);
    
    #
    # The COM file gives the pre-existing community assignment for the nodes
    # TODO: manage overlapping communities
    #
    open ( COM, "<", $prefix."_community.dat")
        or die ("Error in opening community file ".$prefix."_community.dat for reading: $!\n");
    
    while ( <COM> ) {
        if ( /^(\d+)\s(\d+)/ ) {
            if ( $G->has_vertex($1) ) {
                $G->set_vertex_attribute( $1, "value", $2 );
                #print "Node $1 has community $2\n";
            }
            else {die("Error in assigning community $2 to non-existing vertex $1 in ".$prefix."_community.dat.\n");}
        }
    }
    close (COM);
    
    return $G;
}


#
# Parse a DGS file
# TODO: manage weight from dgs file ?
#
sub parse_dgs {
    my $file = shift;
    my %parameters = @_;
    
    #
    # Check that the parameter step is present if the parameter graph is
    # present
    #
    if (exists($parameters{graph}) && !exists($parameters{step})) {
        die("Error: updating a graph from a DGS file requires current step information.\n
            Please use \"parse(graphfile, graph => G, step => s)\".\n");
    }
    
    #
    # Test which version of dgs should be used
    #
    open( DGS, "<", $file ) or die ("Error in opening DGS file $file for reading: $!\n");
    my @lines = <DGS>;
    close(DGS);
    
    if (grep(/^DGS00(1|2)/, $lines[0])) {
        _parse_dgs_v12($file, %parameters);
    }
    else {
        die("Error: parsing for DGS version $lines[0] is not yet implemented.\n");
    }
}

sub _parse_dgs_v12 {
    my $file = shift;
    my %parameters = @_;
    
    #
    # Create a new graph or use the one specified in the parameters
    #
    my $G;
    my $step;
    unless (exists($parameters{graph})) {
        if (exists($parameters{directed})) {
            $G = Graph->new( directed => 1 );
        }
        else {
            $G = Graph->new( undirected => 1 );
        }
        $step = 0;
    }
    else {
        $G = $parameters{graph};
        $step = $parameters{step};
    }
    
    #
    # Read the file until the end of the requested step
    # Also record the highest step
    #
    open( DGS, "<", $file ) or die ("Error in opening DGS file $file for reading: $!\n");
    my $in_current_step = 0;
    my $max_steps = 0;
    while (<DGS>) {
        #
        # Entering/leaving the current step
        #
        if (/^st $step$/) {
            $in_current_step = 1;
            #print "current step = $step\n";
        }
        elsif (/^st (\d+)$/) {
            $max_steps = $1;
            last if ($1 > $step && exists($parameters{graph}));
            $in_current_step = 0;
        }
        #
        # Process the information of the current step
        #
        elsif ($in_current_step) {
            #an "0" 42.739232029808754 248.5905818079476
            #cn "1" 255.71367733451382 119.91483191177676
            if (/^(a|c)n "(\d+)" (\d+\.?\d*) (\d+\.?\d*)/) {
                #print "$1 $2 $3 $4\n";
                $G->add_vertex(($2+1)) if ($1 eq "a");
                $G->set_vertex_attribute(($2+1), "x", $3);
                $G->set_vertex_attribute(($2+1), "y", $4);
            }
            #dn "0"
            elsif (/^dn "(\d+)"$/) {
                $G->delete_vertex(($1+1));
            }
            #ae "38:41:ieee802.11b" "37" "40"
            #ce "38:41:ieee802.11b" "37" "40"
            elsif (/^(a|c)e "(.*)" "(\d+)" "(\d+)"$/) {
                #print "$1 $2 $3 $4\n";
                $G->add_weighted_edge(($3+1), ($4+1), 1) if ($1 eq "a");
                $G->set_edge_attribute(($3+1), ($4+1), "ae", $step);
                $G->set_edge_attribute(($3+1), ($4+1), "name", $2);
            }
            #de "59:85:ieee802.11b"
            elsif (/^de "((\d+):(\d+):.*)"$/) {
                #print "$1 $2 $3\n";
                $G->delete_edge($2, $3);
            }
        }
    }
    close(DGS);
    
    if (exists($parameters{graph})) {
        return ($G, ($step+1));
    }
    else {
        return ($G, $max_steps);
    }
}
1;
