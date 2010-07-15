#!/bin/bash

if [ ! -d 'rand' ]; then
	mkdir 'rand'
fi

for k in 10 20 30 40 50 60 70 80 90 100; do
	for run in {0..10}; do
		
		echo "$run" > 'time_seed.dat'
		./benchmark -rand -N 1000 -k "$k" -maxk 200 >> rand.log
		mv 'network.dat' rand/rand-1000-200-"$k"-"$run"_network.dat
		mv 'community.dat' rand/rand-1000-200-"$k"-"$run"_community.dat
		mv 'statistics.dat' rand/rand-1000-200-"$k"-"$run"_statistics.dat
	done
done