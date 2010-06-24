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
use Math::Random qw(random_set_seed random_exponential);       # Better random number generator
use Data::Dumper;


our $VERSION = '0.1';
our @EXPORT  = qw(generate_content_distribution get_content_distribution content_similarity);

sub generate_content_distribution {
    my $G = shift;
    my %parameters = @_;
    
    #
    # Check that necessary parameters are present
    #
    unless (exists($parameters{content_min})) {
        die("Error: the content distribution generation requires the optional argument content_min.
            Please use \"generate_content_distribution(\$G, content_min => \$n)\".\n");
    }
    
    unless (exists($parameters{content_exp})) {
        die("Error: the content distribution generation requires the optional argument content_exp.
            Please use \"generate_content_distribution(\$G, content_exp => \$e)\".\n");
    }
    
    unless (exists($parameters{content_types})) {
        die("Error: the content distribution generation requires the optional argument content_types.
            Please use \"generate_content_distribution(\$G, contencontent_typest_nb => \$t)\".\n");
    }
    
    random_set_seed(($parameters{seed} + 1 , 13*$parameters{seed} + 7));
    
    foreach my $n ($G->vertices) {
        # Set the actual number of elements in the node
        # Follows a Pareto distribution
        # see: http://en.wikipedia.org/wiki/Pareto_distribution
        $G->set_vertex_attribute($n, "content_nb",
            int ($parameters{content_min} * exp (random_exponential(1, $parameters{content_exp}))) );
        
        # Sets the distribution
        my @distribution;
        for (my $t=0; $t < $parameters{content_types}; $t++) {
            $distribution[$t] = exp ( random_exponential(1, 1.5) );
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
    
    my $nb = $G->get_vertex_attribute($n, "content_nb");
    my $dist = $G->get_vertex_attribute($n, "content_dist");
    
    return ($nb, $dist);
}

sub content_similarity {
    my $G = shift;
    my $n1 = shift;
    my $n2 = shift;
    
    #
    # Retrieve the distribution of both nodes
    #
    my ($nb1, $dist1) = get_content_distribution($G, $n1);
    my ($nb2, $dist2) = get_content_distribution($G, $n2);

    #
    # Return 1 - Hellinger_distance of the two dists
    # so the metric is in [0;1] (as the stability metric), 1 being the best
    #
    if ($n1 == $n2) {
        return 1;
    }
    else {
        return 1 - _hellinger_distance($dist1, $dist2);
    }
}

#
# Compute the Hellinger distance of two distributions
# see: http://en.wikipedia.org/wiki/Hellinger_distance
#
sub _hellinger_distance {
    my $dist1 = shift;
    my $dist2 = shift;
    
    #
    # First compute the Bhattacharyya coefficient
    # see: http://en.wikipedia.org/wiki/Bhattacharyya_distance
    #
    my $bc = 0;
    for (my $t=0; $t<(scalar @{$dist1}); $t++) {
        $bc += sqrt( $dist1->[$t] * $dist2->[$t] ) if ($dist2->[$t]);
    }
    
    #
    # Now compute the Hellinger distance, based on the Bhattacharyya coefficient
    #
    return sqrt(1 - $bc);
}
