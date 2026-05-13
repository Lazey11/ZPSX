#!/usr/bin/env fish

set bios /home/user/psxtests/PS1_BIOS/SCPH1001.bin

set tests \
    "/home/user/psxtests/PSX/GPU/16BPP/MemoryTransfer/MemoryTransfer16BPP.exe 0xD7E8890E" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderLine/RenderLine16BPP.exe 0xB696EC0C" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderPolygon/RenderPolygon16BPP.exe 0xDB9B6861" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderPolygonClip/RenderPolygonClip16BPP.exe 0x9BBB1C5C" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderPolygonDither/RenderPolygonDither16BPP.exe 0x7F3630BD" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderRectangle/RenderRectangle16BPP.exe 0x9626A981" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderRectangleClip/RenderRectangleClip16BPP.exe 0xAD1C6E99" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygon/15BPP/RenderTexturePolygon15BPP.exe 0xBE1231BC" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygon/CLUT4BPP/RenderTexturePolygonCLUT4BPP.exe 0x9C16E5CB" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygon/CLUT8BPP/RenderTexturePolygonCLUT8BPP.exe 0xE1E777F7" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygon/MASK15BPP/RenderTexturePolygonMASK15BPP.exe 0x2CA9926F" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonClip/15BPP/RenderTexturePolygonClip15BPP.exe 0xB165E8F2" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonClip/CLUT4BPP/RenderTexturePolygonClipCLUT4BPP.exe 0x782A31FD" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonClip/CLUT8BPP/RenderTexturePolygonClipCLUT8BPP.exe 0x05DBA3C1" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonClip/MASK15BPP/RenderTexturePolygonClipMASK15BPP.exe 0x2EDC9E6B" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonDither/RenderTexturePolygon15BPPDither.exe 0x9F138BA1" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTextureRectangle/15BPP/RenderTextureRectangle15BPP.exe 0xD9D371DF" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTextureRectangle/CLUT4BPP/RenderTextureRectangleCLUT4BPP.exe 0xC31E0C3A" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTextureRectangle/CLUT8BPP/RenderTextureRectangleCLUT8BPP.exe 0xBEEF9E06" \
    "/home/user/psxtests/PSX/GPU/16BPP/RenderTextureRectangle/MASK15BPP/RenderTextureRectangleMASK15BPP.exe 0x5AF99EB3"

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
