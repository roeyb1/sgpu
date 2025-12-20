#if OS == .WINDOWS {
    #load "windows.jai";
} else #if OS == .LINUX {
    SLANG_FAILED :: (status: s32) -> bool {
        return status < 0;
    }

    SLANG_SUCCEEDED :: (status: s32) -> bool {
        return status >= 0;
    }

    SLANG_GET_RESULT_FACILITY :: (r: s32) -> s32 {
        return (r >> 16) & 0x7fff;
    }

    SLANG_GET_RESULT_CODE :: (r: s32) -> s32 {
        return r & 0xffff;
    }

    SLANG_MAKE_ERROR :: (fac: s32, code: s32) -> s32 {
        return (fac << 16) | code | cast(s32, 0x80000000);
    }

    SLANG_MAKE_SUCCESS :: (fac: s32, code: s32) -> s32 {
        return (fac << 16) | cast(s32, code);
    }

    #load "linux.jai";
} else {
    #assert false "Unsupported OS for Slang";
}

#if OS == .WINDOWS {
    slang_compiler :: #library,no_dll,link_always "win/slang-compiler";
} else #if OS == .LINUX {
    libslang :: #library "linux/libslang";
}

