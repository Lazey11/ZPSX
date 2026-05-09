#!/usr/bin/env fish

set -q BIOS; or set BIOS /home/user/psxtests/PS1_BIOS/SCPH1001.bin
set -q PAD_TEST; or set PAD_TEST $HOME/psxtests/ps1-tests/input/pad/pad.exe
set -q CPUADD_TEST; or set CPUADD_TEST $HOME/psxtests/PSX/CPUTest/CPU/ADD/CPUADD.exe

zig build -Doptimize=ReleaseFast; or exit 1

set pad_log (mktemp)
set cpuadd_log (mktemp)

./zig-out/bin/ZPSX $BIOS $PAD_TEST --headless --frames 60 >$pad_log 2>&1; or begin
    cat $pad_log
    rm -f $pad_log $cpuadd_log
    exit 1
end

grep -q "Loaded PS-EXE .*pad.exe" $pad_log; or begin
    echo "pad smoke failed: missing Loaded PS-EXE line"
    cat $pad_log
    rm -f $pad_log $cpuadd_log
    exit 1
end

./zig-out/bin/ZPSX $BIOS $CPUADD_TEST --headless --frames 10 >$cpuadd_log 2>&1; or begin
    cat $cpuadd_log
    rm -f $pad_log $cpuadd_log
    exit 1
end

grep -q "Loaded PS-EXE .*CPUADD.exe" $cpuadd_log; or begin
    echo "CPUADD smoke failed: missing Loaded PS-EXE line"
    cat $cpuadd_log
    rm -f $pad_log $cpuadd_log
    exit 1
end

cat $pad_log
cat $cpuadd_log
rm -f $pad_log $cpuadd_log

echo "smoke tests passed"
