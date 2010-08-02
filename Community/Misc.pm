##############################################################################
# File   : Community/Misc.pm
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
package Community::Misc;

use strict;
use warnings;
use base 'Exporter';

use List::Util 'shuffle';
use UUID;

our $VERSION = '0.1';
our @EXPORT  = qw(  node_info
                    get_node_community
                    reset_node_community
                    set_node_community
                    is_bridge
                    get_originator_distance
                    set_originator_distance
                    path_weight);

sub node_info {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my $str = "$n<".get_node_community($G, $n, %parameters).">";
    $str .= "(".get_originator_distance($G, $n, %parameters).")"
        if $G->has_vertex_attribute($n, "originator_distance");
        
    return $str;
}

sub neighborhood_info {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my $str;
    foreach my $nb ($G->neighbours($n)) {
        $str .= node_info($G, $nb, %parameters)." ";
    }
    return $str;
}


sub get_node_community {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my $community_field = exists($parameters{community_field}) ?
        $parameters{community_field} : "community";
    
    unless($G->has_vertex_attribute($n, $community_field)) {
        reset_node_community($G, $n, %parameters);
    }
    return $G->get_vertex_attribute($n, $community_field);
}

sub reset_node_community {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my $uuid;
    my $string;
    UUID::generate($uuid);
    UUID::unparse($uuid, $string);
    set_node_community($G, $n, $string, %parameters);
}

sub set_node_community {
    my $G = shift;
    my $n = shift;
    my $c = shift;
    my %parameters = @_;
    
    my $community_field = exists($parameters{community_field}) ?
        $parameters{community_field} : "community";
    
    $G->set_vertex_attribute($n, $community_field, $c);
}

#
# Tells if a link is between two communities
#
sub is_bridge {
    my $G = shift;
    my $u = shift;
    my $v = shift;
    my %parameters = @_;
    
    return (get_node_community($G, $u, %parameters) !=
    get_node_community($G, $v, %parameters));
}

sub get_originator_distance {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my $od_field = exists($parameters{originator_distance_field}) ?
        $parameters{originator_distance_field} : "originator_distance";
    
    if ($G->has_vertex_attribute($n, $od_field)) {
        return $G->get_vertex_attribute($n, $od_field);
    }
    elsif (get_node_community($G, $n, %parameters) == $n){
        return 0;
    }
    else {
        die("Error: unknown distance to originator.\n");
    }
}

sub set_originator_distance {
    my $G = shift;
    my $n = shift;
    my $d = shift;
    my %parameters = @_;
    
    my $od_field = exists($parameters{originator_distance_field}) ?
        $parameters{originator_distance_field} : "originator_distance";
    
    $G->set_vertex_attribute($n, $od_field, $d);
}

#
# Returns the path weight between two nodes, ie :
# - the edge weight if the two nodes are direct neighbors
# - the path min-weight ("weakest link") if the two nodes are connected
# - 0 if they are disconnected
#
sub path_weight {
    my $G = shift;
    my $u = shift;
    my $v = shift;
    my %parameters = @_;
    
    # The current node and the considered node are neighbors
    # use the link weight to consctruct the distribution
    if ($G->has_edge($u, $v)) {
        return $G->get_edge_attribute($u, $v, "weight");
    }
    # Otherwise the two nodes are undirect neighbors, use the weakest
    # weight on the path as weight
    # NOTE: this assume "positive" weight measure (higher weight is better...)
    else {
        my @path = $G->SP_Dijkstra($u, $v);
        return 0 unless (scalar @path > 0);
        my $min_weight = 2**32;
        for (my $i = 0; $i < (scalar @path)-2; $i++) {
            my $weight = $G->get_edge_attribute($path[$i], $path[$i+1], "weight");
            $min_weight = $weight if ($weight < $min_weight);
        }
        return $min_weight;
    }
}

