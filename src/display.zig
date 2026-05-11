const std = @import("std");
const debugPrint = std.debug.print;
const C = @import("C");
const gpu_f = @import("gpu.zig");

pub const EmuState = enum {
    RUNNING,
    PAUSED,
    Quit,
};

pub const SDL = struct {
    window: ?*C.SDL_Window = null,
    renderer: ?*C.SDL_Renderer = null,
    texture: ?*C.SDL_Texture = null,
};

pub const displayConfig = struct {
    windowWidth: u32,
    windowHeight: u32,
    foregroundColor: u32,
    backgroundColor: u32,
};

pub fn displaySetConfig(displayconfig: *displayConfig) !void {
    displayconfig.* = .{
        .windowWidth = 640,
        .windowHeight = 480,
        .foregroundColor = 0xFFFFFFFF,
        .backgroundColor = 0x000000FF,
    };
}

pub fn SDL_INIT(sdl: *SDL, config: *displayConfig) !void {
    const windowH: c_int = @intCast(config.windowHeight);
    const windowW: c_int = @intCast(config.windowWidth);
    if (!C.SDL_Init(C.SDL_INIT_VIDEO)) {
        C.SDL_Log("Could not initialize SDL! %s\n", C.SDL_GetError());
        return error.SDLINITFAILED;
    }
    sdl.window = C.SDL_CreateWindow(
        "TEST WINDOW",
        windowW,
        windowH,
        C.SDL_WINDOW_RESIZABLE,
    ) orelse {
        C.SDL_Log("Could not create SDL window! %s\n", C.SDL_GetError());
        return error.SDLWINDOWFAILED;
    };
    sdl.renderer = C.SDL_CreateRenderer(
        sdl.window.?,
        null,
    ) orelse {
        C.SDL_Log("Could not create SDL renderer! %s\n", C.SDL_GetError());
        return error.SDLRENDERERFAILED;
    };
    sdl.texture = C.SDL_CreateTexture(
        sdl.renderer.?,
        C.SDL_PIXELFORMAT_ARGB8888,
        C.SDL_TEXTUREACCESS_STREAMING,
        windowW,
        windowH,
    ) orelse {
        C.SDL_Log("Could not create SDL texture! %s\n", C.SDL_GetError());
        return error.SDLTEXTUREFAILED;
    };
}

pub fn clearScreen(sdl: *SDL, config: displayConfig) !void {
    const r: u8 = @intCast((config.backgroundColor >> 24) & 0xFF);
    const g: u8 = @intCast((config.backgroundColor >> 16) & 0xFF);
    const b: u8 = @intCast((config.backgroundColor >> 8) & 0xFF);
    const a: u8 = @intCast(config.backgroundColor & 0xFF);

    if (!C.SDL_SetRenderDrawColor(sdl.renderer.?, r, g, b, a)) {
        C.SDL_Log("Could not set draw color! %s\n", C.SDL_GetError());
        return error.SDLSetDrawColorFailed;
    }

    if (!C.SDL_RenderClear(sdl.renderer.?)) {
        C.SDL_Log("Could not clear renderer! %s\n", C.SDL_GetError());
        return error.SDLRenderClearFailed;
    }
}

pub fn cleanup(sdl: *SDL) !void {
    if (sdl.texture) |texture| {
        C.SDL_DestroyTexture(texture);
    }
    if (sdl.renderer) |renderer| {
        C.SDL_DestroyRenderer(renderer);
    }
    if (sdl.window) |window| {
        C.SDL_DestroyWindow(window);
    }
    C.SDL_Quit();
}

pub fn updateScreen(sdl: *SDL, config: *displayConfig) !void {
    _ = config;

    if (!C.SDL_RenderPresent(sdl.renderer.?)) {
        C.SDL_Log("Could not present renderer! %s\n", C.SDL_GetError());
        return error.SDLRenderPresentFailed;
    }
}

fn displayWidthScale(display_mode: u32) u32 {
    const hres = display_mode & 0x3;
    return switch (hres) {
        0 => 2,
        1 => 2,
        2 => 1,
        3 => 1,
        else => 2,
    };
}
fn displayIs24Bpp(display_mode: u32) bool {
    return (display_mode & 0x10) != 0;
}
fn vramByte(gpu: *const gpu_f.Gpu, byte_index: u32) u8 {
    const word_index = byte_index / 2;
    if (word_index >= 1024 * 512) return 0;

    const word = gpu.vram[@intCast(word_index)];
    return @intCast(if ((byte_index & 1) == 0)
        word & 0xFF
    else
        (word >> 8) & 0xFF);
}

pub fn drawVramToScreen(sdl: *SDL, config: *displayConfig, gpu: *const gpu_f.Gpu) !void {
    var pixel_raw: ?*anyopaque = null;
    var pitch: c_int = 0;

    if (!C.SDL_LockTexture(sdl.texture.?, null, &pixel_raw, &pitch)) {
        C.SDL_Log("Could not lock texture! %s\n", C.SDL_GetError());
        return error.SDLLOCKTEXTUREFAILED;
    }
    defer C.SDL_UnlockTexture(sdl.texture.?);
    const pixels_byte: [*]u8 = @ptrCast(pixel_raw.?);

    var y: u32 = 0;
    while (y < config.windowHeight) : (y += 1) {
        const row_bytes = pixels_byte + @as(usize, @intCast(y * @as(u32, @intCast(pitch))));
        const row: [*]u32 = @ptrCast(@alignCast(row_bytes));

        var x: u32 = 0;
        while (x < config.windowWidth) : (x += 1) {
            const x_scale = displayWidthScale(gpu.display_mode);
            const display_px = x / x_scale;
            const src_x = @as(u32, gpu.display_x) + display_px;
            const src_y = @as(u32, gpu.display_y) + (y / 2);

            var argb: u32 = 0xFF000000;
            if (src_y < 512) {
                if (displayIs24Bpp(gpu.display_mode)) {
                    const byte_index =
                        (src_y * 2048) +
                        (@as(u32, gpu.display_x) * 2) +
                        (display_px * 3);

                    if (byte_index + 2 < 1024 * 512 * 2) {
                        const r: u32 = vramByte(gpu, byte_index + 0);
                        const g: u32 = vramByte(gpu, byte_index + 1);
                        const b: u32 = vramByte(gpu, byte_index + 2);

                        argb = 0xFF000000 | (r << 16) | (g << 8) | b;
                    }
                } else if (src_x < 1024) {
                    const px = gpu.vram[@intCast(src_y * 1024 + src_x)];

                    const r5: u32 = px & 0x1F;
                    const g5: u32 = (px >> 5) & 0x1F;
                    const b5: u32 = (px >> 10) & 0x1F;

                    const r: u32 = (r5 << 3) | (r5 >> 2);
                    const g: u32 = (g5 << 3) | (g5 >> 2);
                    const b: u32 = (b5 << 3) | (b5 >> 2);

                    argb = 0xFF000000 | (r << 16) | (g << 8) | b;
                }
            }

            row[@intCast(x)] = argb;
        }
    }
    const dst = C.SDL_FRect{
        .x = 0,
        .y = 0,
        .w = @floatFromInt(config.windowWidth),
        .h = @floatFromInt(config.windowHeight),
    };
    if (!C.SDL_RenderTexture(sdl.renderer.?, sdl.texture.?, null, &dst)) {
        C.SDL_Log("Could not render texture! %s\n", C.SDL_GetError());
        return error.SDLRENDERTEXTUREFAILED;
    }
}
