#!/usr/bin/env fish

set -q BIOS; or set BIOS /home/user/psxtests/PS1_BIOS/SCPH1001.bin
set -q PAD_TEST; or set PAD_TEST $HOME/psxtests/ps1-tests/input/pad/pad.exe
set -q CPUADD_TEST; or set CPUADD_TEST $HOME/psxtests/PSX/CPUTest/CPU/ADD/CPUADD.exe

zig build -Doptimize=ReleaseFast; or exit 1

./zig-out/bin/ZPSX $BIOS $PAD_TEST --headless --frames 60; or exit 1
./zig-out/bin/ZPSX $BIOS $CPUADD_TEST --headless --frames 10; or exit 1
