#!/bin/bash

if [ ! -d 'gn' ]; then
	mkdir 'gn'
fi

for mu in 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.75; do
	for run in {0..10}; do
		
		echo "$run" > 'time_seed.dat'
		./benchmark -f 'flags_gn.dat' -mu "$mu" >> gn.log
		mv 'network.dat' gn/gn-"$mu"-"$run"_network.dat
		mv 'community.dat' gn/gn-"$mu"-"$run"_community.dat
		mv 'statistics.dat' gn/gn-"$mu"-"$run"_statistics.dat
	done
done