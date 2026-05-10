#!/usr/bin/env fish

set -q BIOS; or set BIOS /home/user/psxtests/PS1_BIOS/SCPH1001.bin
set -q VISUAL_TEST; or set VISUAL_TEST $HOME/psxtests/PSX/CPUTest/CPU/ADD/CPUADD.exe

zig build -Doptimize=ReleaseFast; or exit 1
./zig-out/bin/ZPSX $BIOS $VISUAL_TEST
