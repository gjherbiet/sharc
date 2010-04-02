##############################################################################
# File   : Utils/Stability.pm
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
package Utils::Stability;

use strict;
use warnings;
use base 'Exporter';

use Graph;

our $VERSION = '0.1';
our @EXPORT  = qw(age quality);

#
# Recompute the link weights using "age"
#
sub age {
    my $G = shift;
    my %parameters = @_;
    
    #
    # Computing age requires the "step" parameter to be set
    #
    unless (exists($parameters{step})) {
        die("Error: the age stability metric requires the optional argument step.
            Please use \"age(\$G, step => \$step)\".\n");
    }
    
    foreach my $endpoints ($G->edges) {
        #
        # Update the weight by comparing to the step it has been created
        # only if this latter information exists
        #
        my ($u, $v) = @{$endpoints};
        if ($G->has_edge_attribute($u, $v, "ae")) {
            my $weight = $parameters{step} - $G->get_edge_attribute($u, $v, "ae");
            $G->set_edge_weight($u, $v, $weight);
        }
    }
}

#
# Recompute the link weights using "quality"
# In this model, this is based on the distance between the nodes and the
# alpha parameter (defaulting to 2.0 to simulate free-space propagation)
#
sub quality {
    my $G = shift;
    my %parameters = @_;
    
    my $alpha = 2;
    $alpha = $parameters{alpha} if (exists($parameters{alpha}));
    
    foreach my $endpoints ($G->edges) {
        #
        # Update the weight based on the endpoints position if this information
        # exists
        #
        my ($u, $v) = @{$endpoints};
        if ($G->has_vertex_attribute($u, "x") && $G->has_vertex_attribute($u, "y") &&
            $G->has_vertex_attribute($v, "x") && $G->has_vertex_attribute($v, "y")) {
                
            my $xx = $G->has_vertex_attribute($u, "x") - $G->has_vertex_attribute($v, "x");
            my $yy = $G->has_vertex_attribute($u, "y") - $G->has_vertex_attribute($v, "y");
            my $dist = sqrt( $xx**2 + $yy**2 );

            my $weight = 1 / ($dist ** $alpha);
            $G->set_edge_weight($u, $v, $weight);
        }
    }
}

