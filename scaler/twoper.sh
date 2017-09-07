#!/bin/bash

#let n=20		# should make two million records
let n=100		# should make 10 million more records
while [[ $n > 0 ]]
do
	echo -n "$n "
	date
	./eggscale.pl scaletest 50000
	let n--
done
