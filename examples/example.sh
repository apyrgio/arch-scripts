#! /bin/bash

export FORCE_WCP="writeback"
export FORCE_CACHE_OBJECTS="512"
export FORCE_CACHE_SIZE="bs"
export FORCE_IODEPTH="16"
export FORCE_THREADS="1"
export FORCE_BENCH_OBJECTS="bounded"
export FORCE_BENCH_SIZE="4M"
export FORCE_BLOCK_SIZE="4k"
export FORCE_TOPOLOGY="bench->cached->sosd"

~/scripts/stress_xseg.sh -l ~/log_folder $@
