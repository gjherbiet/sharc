##############################################################################
# File   : Utils/GraphViz.pm
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
package Utils::GraphViz;

use strict;
use warnings;
use base 'Exporter';

use Graph;              # Graph management library
use GraphViz;           # Perl interface to the GraphViz graphing tool
use Community::Misc;    # Easy access to community information

use Color::Object;

our $VERSION = '0.1';
our @EXPORT  = qw(graphviz_export);

sub graphviz_export {
    my $G =  shift;
    my $outpath = shift;
    my %parameters = @_;
    
    #
    # Get values or set default for some graph attributes
    #
    my $name = "my_graph";
    $name = $parameters{network_name} if(exists($parameters{network_name}));
    
    my $GV = GraphViz->new(directed => $G->is_directed(), layout => 'neato',
        overlap => 'scale', name => $name,
        node => { style => 'filled', shape => 'circle',  height => '.75', width => '.75'});
    
    #
    # Compute the maximum community score over the nodes
    #
    my $max_community_score = 0;
    foreach my $n ($G->vertices()) {
        if ($G->has_vertex_attribute($n, "community_score") &&
            $G->get_vertex_attribute($n, "community_score") > $max_community_score) {
            $max_community_score = $G->get_vertex_attribute($n, "community_score");
        }
    }
    
    #
    # Generate the nodes with proper attributes based on their assignment
    #
    foreach my $n ($G->vertices()) {
        my %attributes = %{$G->get_vertex_attributes($n)};
        $attributes{shape} = 'box' if ($G->get_vertex_attribute($n, "community") == $n);
        $attributes{color} = join(',', _hsv_color_from_community($G, $G->get_vertex_attribute($n, "community")));
        if ($G->has_vertex_attribute($n, "community_score") && $max_community_score > 0) {
            $attributes{width} = $G->get_vertex_attribute($n, "community_score") / $max_community_score;
            $attributes{height} = $attributes{width};
        }
        elsif ($max_community_score > 0) {
            $attributes{width} = 0.1;
            $attributes{height} = 0.1;
        }
        $GV->add_node($n, %attributes);
    }
    
    #
    # Generate the edges
    #
    foreach my $endpoints ($G->edges()) {
        my ($u, $v) = @{$endpoints};
        my %attributes = %{$G->get_edge_attributes($u, $v)};
        $attributes{label} = $attributes{weight} if (exists($attributes{weight}));
        $GV->add_edge($u => $v, %attributes);
    }
    
    #
    # Generate the actual output
    #
    #print $GV->as_text();
    $GV->as_png($outpath."/".$name."_".$parameters{step}.".png");
}

sub _hsv_color_from_community {
    my $G =  shift;
    my $c = shift;
    
    my $string = sprintf("%06X", $c * (255**3 / (scalar $G->vertices)));
    my $m = 2;
    my @groups = unpack "a$m" x (length($string) /$m ), $string;
    
    my $color = Color::Object->newRGB(hex($groups[$c%3]) / 255, hex($groups[(($c%3)+1)%3]) / 255, hex($groups[(($c%3)+2)%3]) / 255);
    my ($h, $s, $v) = $color->asHSV();
    return ($h / 360, $s, $v);
}
