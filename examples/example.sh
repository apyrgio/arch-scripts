#! /bin/bash

export FORCE_WCP="writeback"
export FORCE_CACHE_OBJECTS="512"
export FORCE_CACHE_SIZE_AMPLIFY="2x"
export FORCE_IODEPTH="16"
export FORCE_THREADS="multi"
export FORCE_BENCH_OBJECTS="bounded"
export FORCE_BENCH_SIZE_AMPLIFY="0.25x"
export FORCE_BLOCK_SIZE="4k"
export FORCE_USE_CACHED="yes"

~/scripts/stress_cached.sh -l ~/example_log
