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

our $VERSION = '0.1';
our @EXPORT  = qw(get_node_community set_node_community get_originator_distance set_originator_distance);

sub get_node_community {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my $community_field = exists($parameters{community_field}) ?
        $parameters{community_field} : "community";
    
    if ($G->has_vertex_attribute($n, $community_field)) {
        return $G->get_vertex_attribute($n, $community_field);
    }
    else {
        return $n;
    }
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
