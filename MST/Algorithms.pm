##############################################################################
# File   : MST/Algorithms.pm
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
package MST::Algorithms;

use strict;
use warnings;
use base 'Exporter';

use List::Util 'shuffle';
use Graph;

use Community::Misc;
use Community::Metrics;

our $VERSION = '0.1';
our @EXPORT  = qw(dagrs);

#
# DA-GRS algorithm on a given network or network snapshot
# Returns the total number of operations performed in this step
#
sub dagrs {
    my $G = shift;
    my $trees = shift;
    my %parameters = @_;

    if (exists $parameters{strict} && !exists($parameters{step})) {
        die("Error: when strict mode is used, the optional argument step should be given.\n
            Please use \"dagrs(\$G, strict => 1, step => \$step)\".\n");
    }

    my $period = 1;
    $period = $parameters{period} if (exists $parameters{period});
    
    my $op = 0;
    foreach my $node (shuffle($G->vertices)) {
        #
        # Perform the actual tree generation process
        #
        if ($period == 1 || ($node % $period) == ($parameters{step} % $period)) {
            $op += _dagrs_node($G, $trees, $node, %parameters);
        }
    }

    #
    # Consistency check
    #
    foreach my $k (keys %{$trees}) {
        die("Error: Tree $k is not a single connected component.")
            if ((scalar $trees->{$k}->connected_components()) > 1);
    }
    return $op;
}

#
# Implements the DA-GRS algorithm for one node
# Return the number of operations performed by the node
#
sub _dagrs_node {
    my $G = shift;
    my $trees = shift;
    my $n = shift;
    my %parameters = @_;


    #my $op = $parameters{ope};
    my $op = 0;
    my $updated;    

    if (exists($parameters{strict}) &&
        $G->has_vertex_attribute($n, "dagrs_update") &&
        $G->get_vertex_attribute($n, "dagrs_update") == $parameters{step}) {
        return $op;
    }

    #
    # Init case. Everyone has a token
    #
    unless ($G->has_vertex_attribute($n, "dagrs_label")) {
        $G->set_vertex_attribute($n, "dagrs_label", "J");
        $G->set_vertex_attribute($n, "dagrs_update", $parameters{step});
        
        # Add the tree containing this node
        my $tree = new Graph(undirected => 1);
        $tree->add_vertex($n);
        $trees->{$n} = $tree;
        $G->set_vertex_attribute($n, "dagrs_treeid", $n);
        
        $updated = 1;
        $op++;
        #print "$n: I\n";
    }
    #
    # Rule 1 : Link break on non-token side
    #
    if (!$updated) {
        R1: foreach my $nb (shuffle($G->neighbours($n))) {
            if ($G->has_vertex_attribute($n, "dagrs_edgelabel-$nb") &&
                $G->get_vertex_attribute($n, "dagrs_edgelabel-$nb")  == 1 &&
                !$G->has_edge($n, $nb)) {
                
                $G->set_vertex_attribute($n, "dagrs_label", "J");
                $G->set_vertex_attribute($n, "dagrs_edgelabel-$nb", 0);
                
                $G->set_vertex_attribute($n, "dagrs_update", $parameters{step})
                    if (exists($parameters{strict}));
                
                
                # Split tree that contained the broken edge
                # and generate the two subtrees
                foreach my $t (keys %{$trees}) {
                    if ($trees->{$t}->has_edge($n, $nb)) {
                        # Delete the broken edge from the tree
                        print "Tree ".$trees->{$t}." has edge ($n,$nb)\n";
                        $trees->{$t}->delete_egde($n, $nb);
                        
                        # Get the two disconnected components
                        my $i1 = $trees->{$t}->connected_component_by_vertex($n);
                        my $i2 = $trees->{$t}->connected_component_by_vertex($nb);
                        my @cc1 = $trees->{$t}->connected_component_by_index($i1);
                        my @cc2 = $trees->{$t}->connected_component_by_index($i2);
                        
                        # Create the new subtree and add it to the hash of trees
                        my $tree1 = new Graph(undirected => 1);
                        foreach my $u (@cc1) {
                            $tree1->add_vertex($u);
                            $G->set_vertex_attribute($u, "dagrs_treeid", $n);
                            foreach my $v (@cc1) {
                                $G->set_vertex_attribute($v, "dagrs_treeid", $n);
                                $tree1->add_vertex($v);
                                if ($trees->{$t}->has_vertex($u, $v)) {
                                    $tree1->add_edge($u, $v);
                                }
                            }
                        }
                        $trees->{$n} = $tree1;
                        $G->set_vertex_attribute($n, "dagrs_treeid", $n);
                        
                        # Update the other subtree
                        my $tree2 = new Graph(undirected => 1);
                        foreach my $u (@cc2) {
                            $tree2->add_vertex($u);
                            $G->set_vertex_attribute($u, "dagrs_treeid", $t);
                            foreach my $v (@cc2) {
                                $tree2->add_vertex($v);
                                $G->set_vertex_attribute($v, "dagrs_treeid", $t);
                                if ($trees->{$t}->has_vertex($u, $v)) {
                                    $tree2->add_edge($u, $v);
                                }
                            }
                        }
                        $trees->{$t} = $tree2;
                        $G->set_vertex_attribute($nb, "dagrs_treeid", $t);
                    }
                }
                
                
                $updated = 1;
                $op++;
                #print "$n: R1 ($nb)\n";
                last R1;
            }
        }
    }
    #
    # Rule 2 : Link break on token side
    #
    if (!$updated) {
        R2: foreach my $nb (shuffle($G->neighbours($n))) {
            if ($G->has_vertex_attribute($n, "dagrs_edgelabel-$nb") &&
                $G->get_vertex_attribute($n, "dagrs_edgelabel-$nb")  == 2 &&
                !$G->has_edge($n, $nb)) {

                $G->set_vertex_attribute($n, "dagrs_edgelabel-$nb", 0);
                
                $G->set_vertex_attribute($n, "dagrs_update", $parameters{step})
                    if (exists($parameters{strict}));
                
                # The trees does not need to be updated with this rule
                
                $updated = 1;
                $op++;
                #print "$n: R2 ($nb)\n";
                last R2;
                
            }
        }
    }
    #
    # Rule 3 : token merging process
    #
    if ($G->get_vertex_attribute($n, "dagrs_label") eq "J" && !$updated) {
        
        #
        # Compute the total neigborhood similarity
        # w/o counting neighbors with which I have already merged
        #
        # my $n_sim_ttl = 0;
        #         foreach my $nb ($G->neighbours($n)) {
        #             if ($G->has_vertex_attribute($n, "n_sim-$nb") &&
        #                 (!$G->has_vertex_attribute($n, "dagrs_edgelabel-$nb") ||
        #                 ($G->has_vertex_attribute($n, "dagrs_edgelabel-$nb") &&
        #                 $G->get_vertex_attribute($n, "dagrs_edgelabel-$nb") == 0)) ) {
        #                 $n_sim_ttl += $G->get_vertex_attribute($n, "n_sim-$nb");
        #             }
        #         }
        #         $n_sim_ttl = 1 if ($n_sim_ttl == 0);
        
        
        #
        # Node I will merge with
        #
        my $m; 
        
        #
        # Do I hear about other trees in my community
        #
        my $other_trees = 0;
        
        #
        # Search a possible "m" within neighbors of my community
        #
        my %C = community_assignment($G, %parameters);
        
        #print "($parameters{step}) $n: C(".get_node_community($G, $n, %parameters).")=";
        #print join(' ', @{$C{get_node_community($G, $n, %parameters)}})."\n";
        
        R3C: foreach my $nb (@{$C{get_node_community($G, $n, %parameters)}}) {
            #
            # Check if I hear other tree ids
            #
            if ($G->has_edge($n, $nb) &&
                $G->get_vertex_attribute($n, "dagrs_treeid") !=
                $G->get_vertex_attribute($nb, "dagrs_treeid")) {
                    $other_trees = 1;
                    #print "($parameters{step}) $n: $nb has different tree id\n";
                }
            
            if ( # This is really a neighbor (and not me)
                $nb != $n && $G->has_edge($n, $nb) &&
                # This neighbor also has token
                $G->get_vertex_attribute($nb, "dagrs_label") eq "J" &&
                # This neighbor hasn't been updated this step, unless we are not in strict mode
                (!exists($parameters{strict}) || $G->get_vertex_attribute($nb, "dagrs_update") < $parameters{step})) {
                
                #print "($parameters{step}) $n: will merge with $nb\n";
                $m = $nb;
                last R3C;
            }
        }
        
        #
        # If no "m" is found within my community, check that I dont hear about
        # other trees in my community and search for a suitable node outside
        # my community
        #
        if (!$m && $other_trees == 0) {
            #print "($parameters{step}) $n: no mergeable node found in my community but no other tree heard\n";
            
            R3NC: foreach my $nb (shuffle($G->neighbours($n))) {
                if ( # This is really not in my community
                    get_node_community($G, $n, %parameters) != get_node_community($G, $nb, %parameters) &&
                    # This neighbor also has token
                    $G->get_vertex_attribute($nb, "dagrs_label") eq "J" &&
                    # This neighbor hasn't been updated this step, unless we are not in strict mode
                    (!exists($parameters{strict}) || $G->get_vertex_attribute($nb, "dagrs_update") < $parameters{step})) {

                    #print "($parameters{step}) $n: will merge with $nb\n";
                    $m = $nb;
                    last R3NC;
                }
            }
        }
        elsif (!$m && $other_trees > 0) {
            #print "($parameters{step}) $n: no mergeable node found in my community and other tree heard, skipping merge\n";
        }
        
        #
        # If m is found, proceed to merge
        #
        if ($m) {
            my $nb = $m;
        
        # R3: foreach my $nb (shuffle($G->neighbours($n))) {
        #     if ($G->get_vertex_attribute($nb, "dagrs_label") eq "J" &&
        #         (!exists($parameters{strict}) ||
        #         $G->get_vertex_attribute($nb, "dagrs_update") < $parameters{step})) {
                
                #
                # Test if the merge should be done :
                # This is based on the fraction of total neighborhood similarity
                # achieved by the current neighbor.
                # If the merge was previously skipped then the fraction is
                # added to a remainder which maked the merge more likely to
                # happen next time.
                #
                # my $rd = rand();
                # my $n_sim = 1;
                # $n_sim = $G->get_vertex_attribute($n, "n_sim-$nb")
                #     if ($G->has_vertex_attribute($n, "n_sim-$nb"));
                # $n_sim += $G->get_vertex_attribute($n, "remainder-$nb")
                #     if ($G->has_vertex_attribute($n, "remainder-$nb"));
                # $n_sim = 0.05 if ($n_sim == 0);
                
                #print "($n,$nb) n_sim = $n_sim, n_sim_ttl = $n_sim_ttl, rand = $rd\n";
                
                # if ($rd > $n_sim / $n_sim_ttl) {
                #     #print "($n,$nb) skipping merge\n";
                #     #
                #     # Increment the remainder for this edge
                #     #
                #     #my $remainder = 0;
                #     #$remainder = $G->get_vertex_attribute($n, "remainder-$nb")
                #     #    if ($G->has_vertex_attribute($n, "remainder-$nb"));
                #     $G->set_vertex_attribute($n, "remainder-$nb", $n_sim);
                #     next R3;
                # }
                # 
                # foreach my $n2 ($G->neighbours($n)) {
                #     $G->set_vertex_attribute($n, "remainder-$n2", 0);
                # }
                #print "($n,$nb) doing merge\n";
                #
                # End of merge test
                #
                
            $G->set_vertex_attribute($n, "dagrs_edgelabel-$nb", 2);
            $G->set_vertex_attribute($nb, "dagrs_edgelabel-$n", 1);
            $G->set_vertex_attribute($nb, "dagrs_label", "N");
            
            if (exists($parameters{strict})) {
                $G->set_vertex_attribute($n, "dagrs_update", $parameters{step});
                $G->set_vertex_attribute($nb, "dagrs_update", $parameters{step});
            }
            
            # Merge the two trees
            my $d;
            foreach my $t1 (keys %{$trees}) {
                if ($trees->{$t1}->has_vertex($n)) {
                    #print "Tree ".$trees->{$t1}." has vertex $n\n";
                    $trees->{$t1}->add_edge($n, $nb);
                    $G->set_vertex_attribute($n, "dagrs_treeid", $t1);
                    $G->set_vertex_attribute($nb, "dagrs_treeid", $t1);
                    #print $trees->{$t1}."\n";
                    foreach my $t2 (keys %{$trees}) {
                        if ($trees->{$t2}->has_vertex($nb) && $t2 != $t1) {
                            #print "Tree ".$trees->{$t1}." has vertex $nb\n";
                            foreach my $v ($trees->{$t2}->vertices) {
                                $trees->{$t1}->add_vertex($v);
                                $G->set_vertex_attribute($v, "dagrs_treeid", $t1);
                            }
                            foreach my $e ($trees->{$t2}->edges) {
                                my ($u, $v) = @{$e};
                                $G->set_vertex_attribute($u, "dagrs_treeid", $t1);
                                $G->set_vertex_attribute($v, "dagrs_treeid", $t1);
                                $trees->{$t1}->add_edge($u, $v);
                            }
                            #print $trees->{$t1}."\n";
                            $d = $t2;
                        }
                    }
                }
            }
            #print "Deleting tree ".$trees->{$d}."that contained vertex $nb\n" if ($d);
            delete($trees->{$d}) if ($d);
            
            $updated = 1;
            $op++;            
                #print "$n: R3 ($nb)\n";
                #last R3;
                
            #}
        }
        else {
            #print "($parameters{step}) $n: no mergeable node found in my neighborhood\n";
        }
    }
    #
    # Rule 4 : token movement
    # TODO: add possibility for a more advanced movement strategy
    #
    if ($G->get_vertex_attribute($n, "dagrs_label") eq "J" && !$updated) {
        R4: foreach my $nb (shuffle($G->neighbours($n))) {
            if ($G->get_vertex_attribute($nb, "dagrs_label") eq "N" &&
                $G->has_vertex_attribute($n, "dagrs_edgelabel-$nb") &&
                $G->get_vertex_attribute($n, "dagrs_edgelabel-$nb") > 0 &&
                (!exists($parameters{strict}) ||
                $G->get_vertex_attribute($nb, "dagrs_update") < $parameters{step})) {
                
                $G->set_vertex_attribute($n, "dagrs_label", "N");
                $G->set_vertex_attribute($nb, "dagrs_label", "J");
                $G->set_vertex_attribute($n, "dagrs_edgelabel-$nb", 1);
                $G->set_vertex_attribute($nb, "dagrs_edgelabel-$n", 2);
                
                if (exists($parameters{strict})) {
                    $G->set_vertex_attribute($n, "dagrs_update", $parameters{step});
                    $G->set_vertex_attribute($nb, "dagrs_update", $parameters{step});
                }
                
                # The trees does not need to be updated with this rule
                
                $updated = 1;
                $op++;
                #print "$n: R4 ($nb)\n";
                last R4;
            }
        }
    }
    #print "Node $n did $op operation in this step.\n" if ($op > 0);
    return $op;
}
