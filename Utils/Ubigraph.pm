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
package Utils::Read;

use strict;
use warnings;
use base 'Exporter';

use Graph;              # Graph management library
use Ubigraph;           # Dynamic graph visualization software
use Community::Misc;    # Easy access to community information

our $VERSION = '0.1';
our @EXPORT  = qw(ubigraph_update);

#
# Create an original ubigraph server and graph object
#
sub ubigraph_create {
    my $G =  shift;
    my %parameters = @_;
    
    # Start the server of die
    #TODO
    
    my $UG = new Ubigraph() or
        die("Error in creating new UbiGraph object: $!\n");
        
    # First update the graph
    $parameters{ubigraph_edges} = {};
    ubigraph_update($G, $UG, %parameters);

    return $UG;
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
    
    foreach my $n ($G->vertices) {
        # Create an ubigraph vertex for this vertex if required
        unless ($G->has_vertex_parameter($n, "ubigraph_vertex")) {
            $G->set_vertex_attribute($n, "ubigraph_vertex",
                $UG->Vertex(size => "1");
            );
        }
        # Get the reference to the ubigraph vertex
        my $v = $G->get_vertex_parameter($n, "ubigraph_vertex");
        
        # Now update the style of the edges based on their assignment
        my $c = get_node_community($G, $n, %parameters);
        $v->label("$n <$c>");
        $v->color($c);
        if ($n == $c) {
            $v->shape("cube");
        else {
            $v->shape("sphere");
        }
        # TODO: membership strength for size
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
                $G->get_vertex_attribute($v, "ubigraph_vertex"));
        }
        # Get the reference to the ubigraph edge
        my $e = $ug_edges->{$u."-".$v};
        
        # Now update style of edge based on its properties
        if ($G->is_edge_weighted($u, $v)) {
            $e->width($G->get_edge_weight($u, $v));
        }
        else {$e->width(1);}
        
        if ($G->has_vertex_attribute($u, "x") && $G->has_vertex_attribute($u, "y") &&
            $G->has_vertex_attribute($v, "x") && $G->has_vertex_attribute($v, "y")) {

            my $xx = $G->get_vertex_attribute($u, "x") - $G->get_vertex_attribute($v, "x");
            my $yy = $G->get_vertex_attribute($u, "y") - $G->get_vertex_attribute($v, "y");
            my $dist = sqrt( $xx**2 + $yy**2 );
            
            $e->strength(1/$dist);
        }
        else {$e->strength(1);}
    }
    return $ug_edges;
}
