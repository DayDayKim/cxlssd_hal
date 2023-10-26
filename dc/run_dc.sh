#!/bin/bash

./common_cleanup.sh
cd work
dc_shell -64 -f ../scripts/dc.tcl | tee -i ../logs/dc.log
cd ..
