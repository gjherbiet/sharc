##############################################################################
# File   : MST/Metrics.pm
# Author : Guillaume-Jean Herbiet  <guillaume.herbiet@uni.lu>
#
#
# Copyright (c) 2010 Guillaume-Jean Herbiet     (http://herbiet.gforge.uni.lu)
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
package MST::Metrics;

use strict;
use warnings;
use base 'Exporter';

use List::Util 'shuffle';
use Graph;
use Data::Dumper;

use Community::Misc;
use Community::Metrics;

our $VERSION = '0.1';
our @EXPORT  = qw(operations subtrees trees_distribution performance_ratio tree_bridges mnr);

#
# Number of operations during step
#
sub operations {
    my $G = shift;
    my $trees = shift;
    my %parameters = @_;
    if (exists($parameters{dagrs_operations})) {
        return $parameters{dagrs_operations};
    }
    else {
        return -1;
    }
}


#
# Number of existing subtrees in the network
#
sub subtrees {
    my $G = shift;
    my $trees = shift;
    my %parameters = @_;
    
    return (scalar keys %{$trees});
}

sub trees_distribution {
    my $G = shift;
    my $trees = shift;
    my %parameters = @_;
    
    #
    # Create and add elements to the statistics element
    #
    my $stats = Statistics::Descriptive::Full->new();
    foreach my $t (sort {$a <=> $b} keys %{$trees}) {
        $stats->add_data((scalar $trees->{$t}->edges()));
    }
    
    #
    # Return statistical data
    #
    return ($stats->count(), $stats->mean(), $stats->standard_deviation(),
            $stats->median(), $stats->min(), $stats->max());
}

#
# Performance ratio: number of subtrees over number of connected components
#
sub performance_ratio {
    my $G = shift;
    my $trees = shift;
    my %parameters = @_;
    
    #return subtrees($G, $trees, %parameters) / (scalar $G->connected_components());
    return (scalar $G->connected_components()) / subtrees($G, $trees, %parameters);
}


#
# Number of tree edges that are bridges between two communities
#
sub tree_bridges {
    my $G = shift;
    my $trees = shift;
    my %parameters = @_;
    
    # Count bridges in all the existing trees
    my $bridges = 0;
    foreach my $t (keys %{$trees}) {
        foreach my $endpoints ($trees->{$t}->edges()) {
            my ($u, $v) = @{$endpoints};
            $bridges++ if (is_bridge($G, $u, $v, community_field => "value"));
        }
    }
    my %communities = community_assignment($G, community_field => "value");
    
    if ($bridges > 0) {
        #print "c=".(scalar keys %communities)." n=".$bridges." Q=".(((scalar keys %communities) - 1) / $bridges)."\n";
        return ((scalar keys %communities) - 1) / $bridges;
    }
    else {return -1;}
}

#
# Number of misplaced node ratio: these are the nodes that belong to a
# subtree which is not the subtree covering most nodes of a given community
#
sub mnr {
    my $G = shift;
    my $trees = shift;
    my %parameters = @_;
    
    #
    # Generate a new graph with all subtrees, but w/o the tree_bridges
    #
    my $TG;
    if (exists $parameters{directed}) {$TG = new Graph(directed => 1);}
    else {$TG = new Graph(undirected => 1);}
    foreach my $t (keys %{$trees}) {
        foreach my $endpoints ($trees->{$t}->edges()) {
            my ($u, $v) = @{$endpoints};
            $TG->add_edge($u, $v) if (!is_bridge($G, $u, $v, community_field => "value"));
        }
    }
    
    #
    # For each connected component of the new graph (i.e. subtree bounded
    # to a single community) store the size of the subtree as count for the
    # community
    #
    my %C;
    foreach my $vertices ($TG->connected_components()) {
        my $c = get_node_community($G, $vertices->[0], %parameters);
        $C{$c} = () unless(exists $C{$c});
        push (@{$C{$c}}, scalar @{$vertices});
    }
    #print "ST: ".Dumper(\%C)."\n";
    
    #
    # Now compute the misplaced nodes number
    #
    my $mn = 0;
    foreach my $c (keys %C) {
        my @vals = reverse sort {$a <=> $b} @{$C{$c}};
        #print "ST: ".join("-", @vals)."\n";
        for (my $i=1; $i<(scalar @vals); $i++) {$mn +=  $vals[$i];}
    }
    
    #
    # Return this number over the total number of nodes
    #
    return ($mn/$G->vertices);
}