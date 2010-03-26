##############################################################################
# File   : Community/Metrics.pm
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
package Community::Metrics;

use strict;
use warnings;
use base 'Exporter';

use Statistics::Descriptive;

use Community::Misc;

our $VERSION = '0.1';
our @EXPORT  = qw(assignment modularity nmi distribution);

sub assignment {
    my $G = shift;
    my %parameters = @_;
    
    #
    # Get the community assignment
    #
    my %C = _community_assignment($G, %parameters);
    
    my $str;
    foreach my $c (sort {$a <=> $b} keys %C) {
        my @nodes = sort (@{$C{$c}});
        $str .= $c.":[";
        $str .= join(" ", @nodes);
        chomp($str);
        $str .= "] ";
    }
    chomp($str);
    return $str;
}


sub distribution {
    my $G = shift;
    my %parameters = @_;
    
    #
    # Get the community assignment
    #
    my %C = _community_assignment($G, %parameters);
    
    #
    # Create and add elements to the statistics element
    #
    my $stats = Statistics::Descriptive::Full->new();
    foreach my $c (sort {$a <=> $b} keys %C) {
        $stats->add_data((scalar @{$C{$c}}));
    }
    
    #
    # Return statistical data
    #
    return ($stats->count(), $stats->mean(), $stats->standard_deviation(),
            $stats->median(), $stats->min(), $stats->max());
}


#
# See http://en.wikipedia.org/wiki/Modularity_(networks)
# TODO: make the modularity computation faster!
#
sub modularity {
    my $G = shift;
    my %parameters = @_;
    
    my $Q = 0;
    my $m = $G->edges();
    
    foreach my $n_i ($G->vertices()) {
        my @neighbors = $G->neighbours($n_i);
        
        foreach my $n_j ($G->vertices()) {
            
            my $c_i = get_node_community($G, $n_i, %parameters);
            my $c_j = get_node_community($G, $n_j, %parameters);
            
            if ($c_i == $c_j) {
                my $k_i = $G->degree($n_i);
                my $k_j = $G->degree($n_j);
                my $a_ij = grep($_ eq $n_j, @neighbors) ? 1 : 0;
                $Q += $a_ij - (($k_i * $k_j) / (2 * $m));
            }
        }
    }
    return (1/(2*$m)) * $Q;
}

sub nmi {
    my $G = shift;
    my %parameters = @_;
    
    my $N = $G->vertices();
    my %X;
    my %Y;
    my %XY;
    
    foreach my $n ($G->vertices()) {
        my $community = get_node_community($G, $n, %parameters);
        my $value = get_node_community($G, $n, community_field => "value");
        push(@{$X{$community}}, $n);
        push(@{$Y{$value}}, $n);
        push(@{$XY{$community."-".$value}}, $n);
    }
    
    my $num = 0;
    my $denom = 0;
    foreach my $x (keys %X) {
        $denom += (scalar @{$X{$x}}) * log10( (scalar @{$X{$x}}) / $N );
        foreach my $y (keys %Y) {
            if (exists($XY{$x."-".$y})) {
                $num -= 2 * (scalar @{$XY{$x."-".$y}}) *
                    log10( ((scalar @{$XY{$x."-".$y}}) * $N) / ((scalar @{$X{$x}}) * (scalar @{$Y{$y}})) );
            }
        }
    }
    foreach my $y (keys %Y) {
        $denom += (scalar @{$Y{$y}}) * log10( (scalar @{$Y{$y}}) / $N );
    }
    if ($denom != 0) {
        return $num / $denom;
    }
    else {
        return undef;
    }
}

#-----------------------------------------------------------------------------
# Helper functions
#
sub _community_assignment {
    my $G = shift;
    my %parameters = @_;

    #
    # Get the community assignment
    #
    my %C;
    foreach my $n ($G->vertices()) {
        my $community = get_node_community($G, $n, %parameters);
        push(@{$C{$community}}, $n);
    }
    return %C;
}


sub log10 {
  my $n = shift;
  return log($n)/log(10);
}
