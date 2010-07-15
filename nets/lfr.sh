#!/bin/bash

if [ ! -d 'lfr' ]; then
	mkdir 'lfr'
fi

for N in 1000 5000; do

	for C in "S" "B"; do

		if [ "$C" = "S" ]; then
			minc=10
			maxc=50
		else
			minc=20
			maxc=100
		fi
		
		for mu in 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80  0.90; do
			for run in {0..10}; do
			
				echo "$run" > 'time_seed.dat'
				./benchmark -f 'flags_lfr.dat' -N "$N" -mu "$mu" -minc "$minc" -maxc "$maxc" >> lfr.log
				mv 'network.dat' lfr/lfr-"$N"-"$C"-"$mu"-"$run"_network.dat
				mv 'community.dat' lfr/lfr-"$N"-"$C"-"$mu"-"$run"_community.dat
				mv 'statistics.dat' lfr/lfr-"$N"-"$C"-"$mu"-"$run"_statistics.dat
		
			done
		done
	
	done

done