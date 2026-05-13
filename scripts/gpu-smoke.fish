#!/usr/bin/env fish

set bios /home/user/psxtests/PS1_BIOS/SCPH1001.bin

set tests \
    "/home/user/psxtests/PSX/GPU/16BPP/MemoryTransfer/MemoryTransfer16BPP.exe 0xD7E8890E" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderLine/RenderLine16BPP.exe 0xB696EC0C" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderPolygon/RenderPolygon16BPP.exe 0xDB9B6861" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderPolygonClip/RenderPolygonClip16BPP.exe 0x9BBB1C5C" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderPolygonDither/RenderPolygonDither16BPP.exe 0x7F3630BD" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderRectangle/RenderRectangle16BPP.exe 0x9626A981" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderRectangleClip/RenderRectangleClip16BPP.exe 0xAD1C6E99"

zig build -Doptimize=ReleaseFast; or exit 1

for entry in $tests
    set parts (string split " " $entry)
    set test $parts[1]
    set expected $parts[2]

    echo "GPU smoke: $test"

    set output (./zig-out/bin/ZPSX $bios $test --headless --frames 120 --gpu-crc 2>&1)
    or begin
        echo "$output"
        exit 1
    end

    if string match -q "*UNSUPPORTED GP0*" $output
        echo "Unsupported GP0 found in $test"
        echo "$output" | rg "UNSUPPORTED GP0" | sort | uniq -c | sort -nr | head -n 20
        exit 1
    end

    set actual (string match -r "GPU VRAM CRC32: 0x[0-9A-Fa-f]+" $output | string replace "GPU VRAM CRC32: " "")

    if test "$actual" != "$expected"
        echo "GPU CRC mismatch for $test"
        echo "expected: $expected"
        echo "actual:   $actual"
        exit 1
    end
end

echo "gpu smoke tests passed"
