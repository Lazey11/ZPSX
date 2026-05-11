#!/usr/bin/env fish

set bios /home/user/psxtests/PS1_BIOS/SCPH1001.bin
set tests \
    /home/user/psxtests/PSX/GPU/16BPP/RenderLine/RenderLine16BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderRectangle/RenderRectangle16BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderPolygon/RenderPolygon16BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderPolygonDither/RenderPolygonDither16BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygon/CLUT4BPP/RenderTexturePolygonCLUT4BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygon/CLUT8BPP/RenderTexturePolygonCLUT8BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygon/15BPP/RenderTexturePolygon15BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTextureRectangle/CLUT4BPP/RenderTextureRectangleCLUT4BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTextureRectangle/CLUT8BPP/RenderTextureRectangleCLUT8BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTextureRectangle/15BPP/RenderTextureRectangle15BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTextureRectangle/MASK15BPP/RenderTextureRectangleMASK15BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderRectangleClip/RenderRectangleClip16BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderPolygonClip/RenderPolygonClip16BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonClip/CLUT4BPP/RenderTexturePolygonClipCLUT4BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonClip/CLUT8BPP/RenderTexturePolygonClipCLUT8BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonClip/15BPP/RenderTexturePolygonClip15BPP.exe \
    /home/user/psxtests/PSX/GPU/16BPP/RenderTexturePolygonClip/MASK15BPP/RenderTexturePolygonClipMASK15BPP.exe

if not test -f $bios
    echo "missing BIOS: $bios"
    exit 1
end

zig build -Doptimize=ReleaseFast
or exit 1

for test in $tests
    if not test -f $test
        echo "missing test: $test"
        exit 1
    end

    echo "GPU smoke: $test"

    ./zig-out/bin/ZPSX $bios $test --headless --frames 120 2> debug.txt
    or exit 1

    if grep -q "UNSUPPORTED GP0" debug.txt
        echo "unsupported GP0 found in $test"
        grep "UNSUPPORTED GP0" debug.txt | sort | uniq -c | sort -nr | head -n 20
        exit 1
    end
end

echo "gpu smoke tests passed"
