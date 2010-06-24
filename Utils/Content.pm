##############################################################################
# File   : Utils/Content.pm
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
package Utils::Content;

use strict;
use warnings;
use base 'Exporter';

use Graph;              # Graph management library
use Data::Dumper;


our $VERSION = '0.1';
our @EXPORT  = qw(generate_content_distribution get_content_distribution);

sub generate_content_distribution {
    my $G = shift;
    my %parameters = @_;
    
    #
    # Check that necessary parameters are present
    #
    unless (exists($parameters{content_nb})) {
        die("Error: the content distribution generation requires the optional argument content_nb.
            Please use \"generate_content_distribution(\$G, content_nb => \$n)\".\n");
    }
    unless (exists($parameters{content_types})) {
        die("Error: the content distribution generation requires the optional argument content_types.
            Please use \"generate_content_distribution(\$G, contencontent_typest_nb => \$t)\".\n");
    }
    
    foreach my $n ($G->vertices) {
        # Set the actual number of elements in the node
        $G->set_vertex_attribute($n, "content_nb", int(rand($parameters{content_nb})) );
        
        # Sets the distribution
        my @distribution;
        for (my $t=0; $t < $parameters{content_types}; $t++) {
            $distribution[$t] = rand();
        }
        # Normalize the distribtion
        @distribution = map( $_ / eval(join '+', @distribution), @distribution);
        # Assign it to the node
        $G->set_vertex_attribute($n, "content_dist", \@distribution);
        #print "$n (".$G->get_vertex_attribute($n, "content_nb")."): ".Dumper($G->get_vertex_attribute($n, "content_dist"));
    }
}

sub get_content_distribution {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my $nb = $G->get_vertex_attribute($n, "content_nb");
    my $dist = $G->get_vertex_attribute($n, "content_dist");
    
    return ($nb, $dist);
}

