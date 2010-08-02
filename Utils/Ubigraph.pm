##############################################################################
# File   : Utils/Ubigraph.pm
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
package Utils::Ubigraph;

use strict;
use warnings;
use base 'Exporter';

use Graph;              # Graph management library
use Ubigraph;           # Dynamic graph visualization software
use Community::Misc;    # Easy access to community information

our $VERSION = '0.1';
our @EXPORT  = qw(ubigraph_create ubigraph_update);

#
# Create an original ubigraph server and graph object
#
sub ubigraph_create {
    my $G =  shift;
    my %parameters = @_;
    
    my $UG = new Ubigraph() or
        die("Error in creating new UbiGraph object: $!\n");
        
    # First update the graph
    $parameters{ubigraph_edges} = {};
    my $ug_edges;
    ($UG, $ug_edges) = ubigraph_update($G, $UG, %parameters);
    
    return ($UG, $ug_edges);
}

#
# Update the complete Ubigraph based on changes in the "formal" graph
#
sub ubigraph_update {
    my $G =  shift;
    my $UG = shift;
    my %parameters = @_;
    
    unless (exists($parameters{ubigraph_edges})) {
        die("Error: Ubigraph update requires the hash reference of ubigraph edges to be passed as argument.
        Please use \"ubigraph_update(\$G, \$UG, ubigraph_edges => \\\%ug_edges)\".\n");
    }
    
    # Update vertices properies
    _update_vertices($G, $UG, %parameters);
    
    # Update edges
    my $ug_edges = _update_edges($G, $UG, %parameters);

    return ($UG, $ug_edges);
}

sub _update_vertices {
    my $G =  shift;
    my $UG = shift;
    my %parameters = @_;
    
    my $max_community_score = 0;
    
    foreach my $n ($G->vertices) {
        # Create an ubigraph vertex for this vertex if required
        unless ($G->has_vertex_attribute($n, "ubigraph_vertex")) {
            $G->set_vertex_attribute($n, "ubigraph_vertex",
                $UG->Vertex(size => "1"));
        }
        # Get the reference to the ubigraph vertex
        my $v = $G->get_vertex_attribute($n, "ubigraph_vertex");
        
        # Now update the style of the edges based on their assignment
        my $c = get_node_community($G, $n, %parameters);
        $v->label("$n");
        # my $mod = $c%3;
        #         my @c;
        #         $c[$mod] = sprintf("%02X", $c * (255 / (scalar $G->vertices)));
        #         $c[($mod+1)%3] = sprintf("%02X", int($c / 3) * (255 / (scalar $G->vertices) / 3));
        #         $c[($mod+2)%3] = sprintf("%02X", int($c / 9) * (255 / (scalar $G->vertices) / 9));
        #         my $col = join("", @c);
        #my $col = _hex_color_from_community($G, $c);
        my $col = _hex_color_from_uuid($c);
        $v->color("#".$col);
        #if ($n == $c) {
        #    $v->shape("cube");
        #}
        #else {
            $v->shape("sphere");
        #}
        if ($G->has_vertex_attribute($n, "community_score") &&
            $G->get_vertex_attribute($n, "community_score") > $max_community_score) {
            $max_community_score = $G->get_vertex_attribute($n, "community_score");
        }
    }
    
    foreach my $n ($G->vertices) {
        my $v = $G->get_vertex_attribute($n, "ubigraph_vertex");
        if ($G->has_vertex_attribute($n, "community_score") &&
            $G->has_vertex_attribute($n, "community_score") != 0) {
            $v->size(2*$G->get_vertex_attribute($n, "community_score") / $max_community_score);
            #print "$n: size=".(2*$G->get_vertex_attribute($n, "community_score") / $max_community_score)."\n";
        }
        else {
            $v->size(1);
        }
    }
    
}

sub _update_edges {
    my $G =  shift;
    my $UG = shift;
    my %parameters = @_;

    # Delete all the edges that were removed
    my $ug_edges = $parameters{ubigraph_edges};
    foreach my $endpoints (keys %{$ug_edges}) {
        my ($u, $v) = split("-", $endpoints, 2);
        unless ($G->has_edge($u, $v)) {
            $ug_edges->{$endpoints}->remove();
            delete($ug_edges->{$endpoints});
        }
    }
    
    # Now parse all the graph edges for creation and update
    foreach my $endpoints ($G->edges) {
        my ($u, $v) = @{$endpoints};
        
        # Edge doesn't exits, create it
        unless (exists($ug_edges->{$u."-".$v})) {
            $ug_edges->{$u."-".$v} = $UG->Edge(
                $G->get_vertex_attribute($u, "ubigraph_vertex"),
                $G->get_vertex_attribute($v, "ubigraph_vertex"),
                #showstrain => "true");
                color => "#ffffff");
        }
        # Get the reference to the ubigraph edge
        my $e = $ug_edges->{$u."-".$v};
        
        # Now update style of edge based on its properties
        if ($G->has_edge_weight($u, $v) && $G->get_edge_weight($u, $v) != 1) {
            $e->width($G->get_edge_weight($u, $v));
        }
        else {$e->width("2");}
        
        if ($G->has_vertex_attribute($u, "x") && $G->has_vertex_attribute($u, "y") &&
            $G->has_vertex_attribute($v, "x") && $G->has_vertex_attribute($v, "y")) {

            my $xx = $G->get_vertex_attribute($u, "x") - $G->get_vertex_attribute($v, "x");
            my $yy = $G->get_vertex_attribute($u, "y") - $G->get_vertex_attribute($v, "y");
            my $dist = sqrt( $xx**2 + $yy**2 );
            $e->strength(25/$dist);
        }
        elsif (get_node_community($G, $u, %parameters) eq get_node_community($G, $v, %parameters)) {
            $e->strength(0.8);
        }
        else {
            $e->strength(0.2);
        }
    }
    return $ug_edges;
}

sub _hex_color_from_community {
    my $G =  shift;
    my $c = shift;
    
    my $string = sprintf("%06X", $c * (255**3 / (scalar $G->vertices)));
    my $m = 2;
    my @groups = unpack "a$m" x (length($string) /$m ), $string;
    return $groups[$c%3].$groups[(($c%3)+1)%3].$groups[(($c%3)+2)%3];
}

sub _hex_color_from_uuid {
    my $uuid = shift;
    
    my @u = split('-', $uuid);
    return join("", map {substr($_, 1, 2)} @u[1,2,3] );
}
