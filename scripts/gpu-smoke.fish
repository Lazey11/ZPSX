#!/usr/bin/env fish

set bios /home/user/psxtests/PS1_BIOS/SCPH1001.bin
set gpu_tests_root /home/user/psxtests/PSX/GPU

zig build -Doptimize=ReleaseFast; or exit 1

for test in (find $gpu_tests_root -iname "*.exe" | sort)
    echo "GPU smoke: $test"

    ./zig-out/bin/ZPSX $bios $test --headless --frames 120 2> /tmp/zpsx-gpu-smoke-debug.txt
    or exit 1

    if grep -q "UNSUPPORTED GP0" /tmp/zpsx-gpu-smoke-debug.txt
        echo "Unsupported GP0 found in $test"
        grep "UNSUPPORTED GP0" /tmp/zpsx-gpu-smoke-debug.txt | sort | uniq -c | sort -nr | head -n 20
        exit 1
    end
end

echo "gpu smoke tests passed"
