#!/bin/bash

if [[ -z $1 ]]; then
	echo "Error: expecting filename to test as argument."
	exit 1;
fi

#
# test the file
#
#echo -n "Testing $1 ... "
cat -e "$1" | /usr/bin/tail -n 1 | grep '\$' &> /dev/null
if [[ $? -eq 1 ]]; then
#	echo "$1 has newline at end, keeping."
#else
	echo "$1 has NO newline at end, DELETING"
	rm -f "$1"
fi