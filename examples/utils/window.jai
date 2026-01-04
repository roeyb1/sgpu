
create_native_window :: (width: int, height: int, name: string) -> u64 {
    // Standard window creation module does not yet support creating a window with Metal surface for macOS.
    // We will use the standard library module on all other platforms.
    #if OS == .MACOS {
        return create_window_metal(width, height, name).(u64);
    } else {
        return create_window(width, height, name);
    }
}

#if OS == .MACOS {
    #load "macos_window.jai";
} else {
    #import "Window_Creation"(DEFAULT_MSAA = 1);
}
