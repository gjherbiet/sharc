##############################################################################
# File   : Community/Algorithms.pm
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
package Community::Algorithms;

use strict;
use warnings;
use base 'Exporter';

use List::Util 'shuffle';

use Community::Misc;

our $VERSION = '0.1';
our @EXPORT  = qw(dummy asynchronous synchronous leung leungsync ecdns sharc);

#-----------------------------------------------------------------------------
# Dummy algorithm, for testing purposes
#
sub dummy {}

#-----------------------------------------------------------------------------
# Synchronous and asynchronous methods
# They are not weighted
#
sub asynchronous {
    my $G = shift;
    my %parameters = @_;

    my $period;
    if (exists $parameters{period} && !exists($parameters{step})) {
        die("Error: when execution period is used, the optional argument step should be given.\n
            Please use \"synchronous(\$G, period => \$p, step => \$step)\".\n");
    }
    elsif (exists $parameters{period}) {
        $period = $parameters{period};
    }
    else {$period = 1;}

    foreach my $node (shuffle($G->vertices)) {
        #
        # Perform the actual community assignment
        #
        if ($period == 1 || ($node % $period) == ($parameters{step} % $period)) {
            #print "Performing ecdns for node $node.\n";
            synchronous_asynchronous_node($G, $node, %parameters);
        }
   }
}

sub synchronous {
    my $G = shift;
    my %parameters = @_;
    
    #
    # The synchronous mode requires the "step" parameter to be set
    #
    unless (exists($parameters{step})) {
        die("Error: the synchronous algorithm requires the optional argument step.
            Please use \"synchronous(\$G, step => \$step)\".\n");
    }
    
    my $period;
    if (exists $parameters{period}) {
        $period = $parameters{period};
    }
    else {$period = 1;}
    
    $parameters{synchronous} = 1;

    foreach my $node (shuffle($G->vertices)) {
        #
        # Perform the actual community assignment
        #
        if ($period == 1 || ($node % $period) == ($parameters{step} % $period)) {
            #print "Performing ecdns for node $node.\n";
            synchronous_asynchronous_node($G, $node, %parameters);
        }
   }
}

sub synchronous_asynchronous_node {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    #
    # Change the default fields used to store the community and the
    # previous community if this is requested by the user
    #
    my $community_field = exists($parameters{community_field}) ?
        $parameters{community_field} : "community";
    my $prev_community_field = exists($parameters{prev_community_field}) ?
        $parameters{prev_community_field} : "prev_".$community_field;
    
    #
    # Store the score of each neighboring community
    #
    my %score;
    
    #
    # Increment the score based on the neighbors current community and
    # neighborhood similarity metric
    #
    foreach my $nb ($G->neighbours($n)) {
        my $nb_community;
        #
        # We are in async mode, or the node hasn't been updated for this step:
        # use he current community field
        #
        if (!exists($parameters{synchronous}) ||
            (!$G->has_vertex_attribute($nb, "update_step") ||
              $G->get_vertex_attribute($nb, "update_step") != $parameters{step}) ){
            #print "$n ($nb): using $community_field.\n";
            $nb_community = get_node_community($G, $nb, community_field => $community_field);
        }
        #
        # Otherwise, use the previous community field
        #
        else {
            #print "$n ($nb): using $prev_community_field.\n";
            $nb_community = get_node_community($G, $nb, community_field => $prev_community_field);
        }
        $score{$nb_community} += 1;
    }
    
    #
    # Now search for the community with the highest score
    #
    my $max_community   = $n;   # if no other community is heard, the node declares
    my $max_score       = -1;   # itself its own community, but this is superseeded
                                # by any other heard community
    foreach my $community (sort keys %score) {
        ($max_score, $max_community) = 
            _max_random_tie($score{$community}, $max_score, $community, $max_community);
    }
    #print "$n: $max_community ($max_score).\n";
    
    if (exists($parameters{synchronous})) {
        $G->set_vertex_attribute($n, "update_step", $parameters{step});
        my $prev_community = get_node_community($G, $n, community_field => $community_field);
        set_node_community($G, $n, $prev_community, community_field => $prev_community_field);
    }
    set_node_community($G, $n, $max_community, community_field => $community_field);
    $G->set_vertex_attribute($n, $community_field."_score", $max_score);
}
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Leung methods
# This is either synchronous or asynchrounous (default is asynchronous),
# always weighted (based on the "weighted" parameter) and used two additional
# parameters m (default 0.1) and delta (default 0.05)
#
sub leung {
    my $G = shift;
    my %parameters = @_;
    
    #
    # The synchronous mode requires the "step" parameter to be set
    #
    if (exists($parameters{synchronous}) && !exists($parameters{step})) {
        die("Error: the Leung synchronous algorithm requires the optional argument step.
            Please use \"leung(\$G, synchronous => 1, step => \$step)\".\n");
    }
    
    my $period;
    if (exists $parameters{period} && !exists($parameters{step})) {
        die("Error: when execution period is used, the optional argument step should be given.\n
            Please use \"synchronous(\$G, period => \$p, step => \$step)\".\n");
    }
    elsif (exists $parameters{period}) {
        $period = $parameters{period};
    }
    else {$period = 1;}

    #
    # Set the default parameters m and delta
    #
    $parameters{m} = 0.1 unless (exists($parameters{m}));
    $parameters{delta} = 0.05 unless (exists($parameters{delta}));

    foreach my $node (shuffle($G->vertices)) {
        #
        # Perform the actual community assignment
        #
        if ($period == 1 || ($node % $period) == ($parameters{step} % $period)) {
            #print "Performing ecdns for node $node.\n";
            leung_node($G, $node, %parameters);
        }
    }
}

sub leungsync {
    my $G = shift;
    my %parameters = @_;
    $parameters{synchronous} = 1;
    leung($G, %parameters);
}



sub leung_node {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    #
    # Change the default fields used to store the community and the
    # previous community if this is requested by the user
    #
    my $community_field = exists($parameters{community_field}) ?
        $parameters{community_field} : "community";
    my $prev_community_field = exists($parameters{prev_community_field}) ?
        $parameters{prev_community_field} : "prev_".$community_field;
        
    #
    # Change the default fields used to store the label_score and the
    # previous community if this is requested by the user
    #
    my $label_score = exists($parameters{label_score}) ?
        $parameters{label_score} : "label_score";
    my $prev_label_score = exists($parameters{prev_label_score}) ?
        $parameters{prev_label_score} : "prev_".$label_score;
    
    #
    # Store the score of each neighboring community
    #
    my %score;
    
    #
    # Maximum label score heard for each neighboring community
    #
    my %max_label_score;
    
    #
    # Increment the score based on the neighbors list of scores for each
    # community
    #
    foreach my $nb ($G->neighbours($n)) {
        my $nb_label_score;
        my $nb_community;
        #
        # We are in async mode, or the node hasn't been updated for this step:
        # use he current community field
        #
        if (!exists($parameters{synchronous}) ||
            (!$G->has_vertex_attribute($nb, "update_step") ||
              $G->get_vertex_attribute($nb, "update_step") != $parameters{step}) ){
                  
            $nb_community = get_node_community($G, $nb, community_field => $community_field);
            $nb_label_score = $G->has_vertex_attribute($nb, $label_score) ?
                $G->get_vertex_attribute($nb, $label_score) : 1;
            
            #print "$n ($nb): using $community_field and $label_score.\n";
            #print "C($nb)=$nb_community, s($nb, $nb_community)=$nb_label_score, d($nb)=".$G->degree($nb).".\n";
        }
        #
        # Otherwise, use the previous community field
        #
        else {
            $nb_label_score = $G->get_vertex_attribute($nb, $prev_label_score);
            $nb_community = get_node_community($G, $nb, community_field => $prev_community_field);
            
            # $nb_label_score = $G->has_vertex_attribute($nb, $prev_label_score) ?
            #                 $G->get_vertex_attribute($nb, $prev_label_score) : 1;
            
            #print "$n ($nb): using $prev_community_field and $prev_label_score.\n";
            #print "C($nb)=$nb_community, s($nb, $nb_community)=$nb_label_score.\n";
        }
        
        #
        # Update the score table
        #
        my $weight = 1;
        $weight = $G->get_edge_weight($nb, $n) if (!exists($parameters{unweighted}));
        
        $score{$nb_community} += $nb_label_score * 
                $G->degree($nb) ** $parameters{m} * $weight;
                
        #
        # Update the maximum label score heard for this community if necessary
        #
        if (!exists($max_label_score{$nb_community}) ||
            $max_label_score{$nb_community} < $nb_label_score) {
                $max_label_score{$nb_community} = $nb_label_score;
        }
    }
    
    # foreach my $c (keys %score) {
    #         print "score($c)=$score{$c} ";
    #     }
    #     print"\n";
    #     
    #     foreach my $c (keys %max_label_score) {
    #         print "max_label_score($c)=$max_label_score{$c} ";
    #     }
    #     print"\n";
    
    
    #
    # Now search for the community with the highest score
    #
    my $max_community   = $n;   # if no other community is heard, the node declares
    my $max_score       = -1;   # itself its own community, but this is superseeded
                                # by any other heard community
    foreach my $community (sort keys %score) {
        ($max_score, $max_community) = 
            _max_random_tie($score{$community}, $max_score, $community, $max_community);
    }
    #
    # Now search for the node with the max community label with the highest score
    #
    my $new_score;
    if (scalar keys %score > 0 && $max_community != $n) {
        $new_score = $max_label_score{$max_community} - $parameters{delta};
    }
    else {
        $new_score = 1;
    }
    
    #print "$n: $max_community ($new_score).\n";
    
    if (exists($parameters{synchronous})) {
        $G->set_vertex_attribute($n, "update_step", $parameters{step});
        
        #
        # Recall the previous label score
        #
        my $prev_score = $G->has_vertex_attribute($n, $label_score) ?
            $G->get_vertex_attribute($n, $label_score) : 1;
        $G->set_vertex_attribute($n, $prev_label_score, $prev_score);
        
        #
        # Recall the previous community id
        #
        my $prev_community = get_node_community($G, $n, community_field => $community_field);
        set_node_community($G, $n, $prev_community, community_field => $prev_community_field);
    }
    #
    # Register the new values
    #
    $G->set_vertex_attribute($n, $label_score, $new_score);
    set_node_community($G, $n, $max_community, community_field => $community_field);
    $G->set_vertex_attribute($n, $community_field."_score", $new_score);
}
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# ECD-NS and SHARC methods
# They are asynchronous and can be weighted, based on the "weighted" parameter
#
sub ecdns {
    my $G = shift;
    my %parameters = @_;
    
    my $period;
    if (exists $parameters{period} && !exists($parameters{step})) {
        die("Error: when execution period is used, the optional argument step should be given.\n
        Please use \"ecdns(\$G, period => \$p, step => \$step)\".\n");
    }
    elsif (exists $parameters{period}) {
        $period = $parameters{period};
    }
    else {$period = 1;}

    foreach my $node (shuffle($G->vertices)) {
        #
        # Perform the actual community assignment
        #
        if ($period == 1 || ($node % $period) == ($parameters{step} % $period)) {
            #print "Performing ecdns for node $node, step is $parameters{step}.\n";
            #print "($node % $period) =".($node % $period)." ($parameters{step} % $period) =".($parameters{step} % $period).".\n";
            ecdns_node($G, $node, %parameters);
        }
    }
}

sub ecdns_node {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    #
    # Construct the cdf of link weigths if required
    #
    my @dist;
    if (!exists($parameters{unweighted})) {
        @dist = _weight_dist($G, $n, %parameters);
        #print "".join(" ", @dist)." l:".(scalar @dist)."\n";
    }
    
    my $community_field = exists($parameters{community_field}) ?
        $parameters{community_field} : "community";
    
    #
    # Store the score of each neighboring community
    #
    my %score;
    
    #
    # Store the highest degree neighbor node for each neighboring community
    #
    my %highest_degree;
    
    #
    # Increment the score based on the neighbors current community and
    # neighborhood similarity metric
    #
    foreach my $nb ($G->neighbours($n)) {
        my $s;
        if (!exists($parameters{unweighted})) {
            # 
            # Search for the index of this weight in the sorted distribution
            # of the link weights
            #
            my $index = 0;
            my $weight = $G->get_edge_attribute($n, $nb, "weight");
            ++$index until $dist[$index] == $weight or $index > $#dist;
            
            #
            # The cdf of the link
            #
            my $cdf = ((scalar @dist) - $index) / (scalar @dist);
            my $ns =_neighborhood_similarity($G, $n, $nb);
            if (exists($parameters{alt})) {
                $s =  $ns ** ((1 / $cdf) - 1);
            }
            else {
                $s =  $ns ** (1 / $cdf);
            }
            #print "w=$weight, i=$index, c=$cdf, ns=$ns, s=$s\n";
        }
        else {
            $s = _neighborhood_similarity($G, $n, $nb);
        }
        $score{get_node_community($G, $nb, %parameters)} += $s;
        
        if (!$highest_degree{get_node_community($G, $nb, %parameters)} ||
            $highest_degree{get_node_community($G, $nb, %parameters)} <
            (scalar $G->neighbours($nb))) {
            $highest_degree{get_node_community($G, $nb, %parameters)} =
            (scalar $G->neighbours($nb));
        }
    }
    
    #
    # Now search for the community with the highest score
    #
    my $max_community   = $n;   # if no other community is heard, the node declares
    my $max_score       = -1;   # itself its own community, but this is superseeded
                                # by any other heard community
    foreach my $community (sort keys %score) {
        print "<$n> $community = $score{$community}\n" if ($n == 6);
        ($max_score, $max_community) = 
            _max_degree_tie($score{$community}, $max_score, $community, $max_community, \%highest_degree);
            #_max_random_tie($score{$community}, $max_score, $community, $max_community);
    }
    #print "$n: $max_community ($max_score).\n";
    set_node_community($G, $n, $max_community, %parameters);
    $G->set_vertex_attribute($n, $community_field."_score", $max_score / (scalar $G->neighbours($n)));
}

sub sharc {
    my $G = shift;
    my %parameters = @_;
    
    #
    # The sharc mode requires the "step" parameter to be set
    #
    unless (exists($parameters{step})) {
        die("Error: the sharc algorithm requires the optional argument step.
            Please use \"sharc(\$G, step => \$step)\".\n");
    }
    
    my $period= 1;
    $period = $parameters{period} if (exists $parameters{period});

    foreach my $node (shuffle($G->vertices)) {
        #
        # Perform the actual community assignment
        #
        if ($period == 1 || ($node % $period) == ($parameters{step} % $period)) {
            #print "Performing ecdns for node $node, step is $parameters{step}.\n";
            #print "($node % $period) =".($node % $period)." ($parameters{step} % $period) =".($parameters{step} % $period).".\n";
            sharc_node($G, $node, %parameters);
        }
    }
}

sub sharc_node {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my $step = $parameters{step};
    
    #
    # Tells if an update has happened
    #
    my $updated = 0;
    
    #
    # Break threshold is the number of "non-fresh"  steps required
    # to enter break mode
    #
    my $break_threshold = 3;
    $break_threshold = $parameters{break_threshold} if (exists($parameters{break_threshold}));
    
    #
    # Break mode lifetime default value
    #
    my $broken_lifetime = 1;
    $broken_lifetime = $parameters{broken_lifetime} if (exists($parameters{broken_lifetime}));
    
    #
    # Get the current node neighbors
    #
    my @neighbors = $G->neighbours($n);
    
    #
    # If the node has no neighbors, simply set myself back to self-community
    #
    if (scalar @neighbors == 0 && !$updated) {
        set_node_community($G, $n, $n, %parameters);
        print "($step) Node $n enters self-community.\n";
        $updated = 1;
    }
    
    #
    # I'm in break mode, and this mode hasn't expired,
    # do nothing but decreasing the break mode lifetime
    # TODO: need to update my distance to originator ????
    #
    if ($G->has_vertex_attribute($n, "broken_community") &&
        $G->has_vertex_attribute($n, "broken_lifetime") &&
        $G->get_vertex_attribute($n, "broken_lifetime") > 0 &&
        !$updated) {
        
        my $bl = $G->get_vertex_attribute($n, "broken_lifetime");
        $G->set_vertex_attribute($n, "broken_lifetime", ($bl -1));
        print "($step) Node $n remains in break mode (".($G->get_vertex_attribute($n, "broken_lifetime"))." remaining).\n";
        $updated = 1;
    }
    #
    # Otherwise, cleanup break mode attributes
    #
    else {
        $G->delete_vertex_attribute($n, "broken_community");
        $G->delete_vertex_attribute($n, "broken_lifetime");
    }
    
    #
    # Now, perform operations on the neighbors to see if I shall enter
    # neighbor break, a new break mode or simply apply ECDNS
    #
    my $originator_distance;
    $originator_distance = 0 if (get_node_community($G, $n, %parameters) == $n);
    
    my $freshness_counter;
    
    foreach my $nb (@neighbors) {
        #
        # Neighbor break mode :
        # I have a neighbor node in break that was in the same community I'm in
        # TODO: need to update my distance to originator ????
        #
        if ($G->has_vertex_attribute($nb, "broken_community") &&
            $G->get_vertex_attribute($nb, "broken_community") == get_node_community($G, $n, %parameters)
            && !$updated) {

            $G->set_vertex_attribute($n, "broken_community",
                get_node_community($G, $n, %parameters));
            $G->set_vertex_attribute($n, "broken_lifetime", $broken_lifetime);
            set_node_community($G, $n, get_node_community($G, $nb, %parameters), %parameters);
            print "($step) Node $n enters neighbor break due to neighbor $nb\n";
            $updated = 1;
        }
        
        #
        # Update the closest distance to originator
        #
        if (get_node_community($G, $n, %parameters) == get_node_community($G, $nb, %parameters) &&
            (!$originator_distance || $originator_distance > get_originator_distance($G, $nb, %parameters))) {
            $originator_distance = get_originator_distance($G, $nb, %parameters) + 1;
            print "($step) Node $n is preliminary ".($originator_distance)." from ".(get_node_community($G, $n, %parameters))." due to neighbor $nb\n";
        }
        
        #
        # Update the freshness counter
        #
        if (get_node_community($G, $n, %parameters) == get_node_community($G, $nb, %parameters) &&
            $G->has_vertex_attribute($nb, "freshness_counter") && 
            (!$freshness_counter || $freshness_counter < $G->get_vertex_attribute($nb, "freshness_counter"))) {
            $freshness_counter = $G->get_vertex_attribute($nb, "freshness_counter");
            print "($step) Node $n sets freshness counter to $freshness_counter due to neighbor $nb\n";
        }
    }
    
    #
    # Should the non fresh steps be increased or reset ?
    #
    if ($G->has_vertex_attribute($n, "freshness_counter") && $freshness_counter &&
        $G->get_vertex_attribute($n, "freshness_counter") >= $freshness_counter &&
        get_node_community($G, $n, %parameters) != $n) {
        my $nf_st = 0;
        $nf_st = $G->get_vertex_attribute($n, "non_fresh_steps")
            if ($G->has_vertex_attribute($n, "non_fresh_steps"));
        $G->set_vertex_attribute($n, "non_fresh_steps", ($nf_st + 1));
        print "($step) Node $n increases non fresh steps to ".($nf_st + 1)."\n";
    }
    else {
        $G->set_vertex_attribute($n, "non_fresh_steps", 0);
        print "($step) Node $n resets non fresh steps to 0\n";
    }
    
    #
    # Enter break mode
    #
    if ($G->get_vertex_attribute($n, "non_fresh_steps") >= $break_threshold &&
        get_originator_distance($G, $n, %parameters) < $originator_distance &&
        !$updated) {
        
        $G->set_vertex_attribute($n, "broken_community",
            get_node_community($G, $n, %parameters));
        $G->set_vertex_attribute($n, "broken_lifetime", $broken_lifetime);
        set_node_community($G, $n, $n, %parameters);
        print "($step) Node $n enters break mode\n";
        $updated = 1;
    }
    
    #
    # If still not updated, apply "simple" ECDNS
    #
    unless ($updated) {
        print "($step) Node $n performs simple ECDNS\n";
        ecdns_node($G, $n, %parameters);
        print "($step) Node $n now has community ".(get_node_community($G, $n, %parameters))."\n";
        $updated = 1;
    }
    
    #
    # Update the distance to (possibly new) originator
    # Update the (possibly new) freshness counter
    #
    if (get_node_community($G, $n, %parameters) == $n) {

        set_originator_distance($G, $n, 0, %parameters);
        
        my $oc = 1;
        $oc = $G->get_vertex_attribute($n, "originator_counter") + 1
            if ($G->has_vertex_attribute($n, "originator_counter"));
        $G->set_vertex_attribute($n, "originator_counter", $oc);
        $G->set_vertex_attribute($n, "freshness_counter", $oc);
        print "($step) Node $n is is own originator, distance to originator is 0, freshness counter is ".($oc)."\n";
    }
    else {
        my $od;
        my $fc = 0;
        $fc = $G->get_vertex_attribute($n, "freshness_counter") if $G->has_vertex_attribute($n, "freshness_counter");
        foreach my $nb (@neighbors) {
            
            #
            # Update the closest distance to originator
            #
            if (get_node_community($G, $n, %parameters) == get_node_community($G, $nb, %parameters) &&
                (!$od || $od > get_originator_distance($G, $nb, %parameters) + 1)) {
                $od = get_originator_distance($G, $nb, %parameters) + 1;
                print "($step) Node $n is ".$od." from ".(get_node_community($G, $n, %parameters))." due to neighbor $nb\n";
            }
            
            #
            # Update the freshness counter
            #
            if (get_node_community($G, $n, %parameters) == get_node_community($G, $nb, %parameters) &&
                $G->has_vertex_attribute($nb, "freshness_counter") &&
                (!$fc || $fc < $G->get_vertex_attribute($nb, "freshness_counter"))) {
                $fc = $G->get_vertex_attribute($nb, "freshness_counter");
                print "($step) Node $n sets freshness counter to $fc due to neighbor $nb\n";
            }
        }
        
        #
        # No originator neighbor is found: this is the case if the node has no
        # neighbor of the same community, consider itself as the max appart
        # from its considered originator
        #
        if (!$od) {
            $od = 2**53;
            print "($step) Node $n has ".(scalar @neighbors)." neighbors but no distance to originator set, setting to maximal value.\n";
        }
        set_originator_distance($G, $n, $od, %parameters);
        $G->set_vertex_attribute($n, "freshness_counter", $fc);
        
        print "($step) Node $n is finally ".$od." from ".(get_node_community($G, $n, %parameters))."\n";
        print "($step) Node $n finally sets freshness counter to $fc\n";
    }
}

#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Helper functions
#
sub _neighborhood_similarity {
    my $G = shift;
    my $n1 = shift;
    my $n2 = shift;
    
    my @neighb1 = $G->neighbours($n1);
    
    unless (grep(/^$n2$/, @neighb1)) {
        die ("Error: computing neighborhood similarity for $n1 with $n2, which is a non-neighbor node.\n");
    }
    my @neighb2 = $G->neighbours($n2);

    #print "$n1: ".join(" ", @neighb1)."\n";
    #print "$n2: ".join(" ", @neighb2)."\n";

    my ($u, $i, $d) = _union_isect_diff(\@neighb1, \@neighb2);
    my $ns = 1 - ( (scalar @{$d}) / ( (scalar @neighb1) + (scalar @neighb2) ) );
    #my $ns = 1 - ( (scalar @{$d}) / (scalar @{$u}) );
    #print $ns."\n";
    return $ns;
}

sub _weight_dist {
    my $G = shift;
    my $n = shift;
    my %parameters = @_;
    
    my @dist;
    
    foreach my $nb ($G->neighbours($n)) {
        push(@dist, $G->get_edge_attribute($n, $nb, "weight"));
    }
    @dist = reverse sort @dist;
    return @dist;
}


sub _union_isect_diff {
    my $set1_ref = shift;
    my $set2_ref = shift;
    
    my @union = ();
	my @intersection = ();
	my @difference = ();
	my %count = ();
	foreach my $element (@{$set1_ref}, @{$set2_ref}) { $count{$element}++; }
	foreach my $element (keys %count) {
		push (@union, $element);
		push (@{$count{$element} > 1 ? \@intersection : \@difference}, $element);
	}
	return(\@union, \@intersection, \@difference);
}

sub _max_random_tie {
    my ($value, $current_max, $candidate, $current_winner) = @_;
	
	# New highest value is found or ex-aequo and tie-break is won
	# Return the new max and the winner candidate;
	if ( $value > $current_max ||
		($value == $current_max && rand() >= 0.5)) {
		return ($value, $candidate);
	}
	# Otherwise, the max value and the winner didn't change
	else {
		return ($current_max, $current_winner);
	}
}

sub _max_degree_tie {
    my ($value, $current_max, $candidate, $current_winner, $degrees) = @_;
	
	# New highest value is found or ex-aequo and tie-break is won
	# Return the new max and the winner candidate;
	if ( $value > $current_max ||
		($value == $current_max && $degrees->{$candidate} > $degrees->{$current_winner})) {
		return ($value, $candidate);
	}
	elsif ($value == $current_max && $degrees->{$candidate} == $degrees->{$current_winner}) {
	    _max_random_tie($value, $current_max, $candidate, $current_winner)
	}
	# Otherwise, the max value and the winner didn't change
	else {
		return ($current_max, $current_winner);
	}
}


#-----------------------------------------------------------------------------

1;