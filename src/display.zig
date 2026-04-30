const std = @import("std");
const debugPrint = std.debug.print;
const C = @import("C");

pub const EmuState = enum {
    RUNNING,
    PAUSED,
    Quit,
};

pub const SDL = struct {
    window: ?*C.SDL_Window = null,
    renderer: ?*C.SDL_Renderer = null,
};

pub const displayConfig = struct {
    windowWidth: u32,
    windowHeight: u32,
    foregroundColor: u32,
    backgroundColor: u32,
};

pub fn displaySetConfig(displayconfig: *displayConfig) !void {
    displayconfig.* = .{
        .windowWidth = 1280,
        .windowHeight = 720,
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
