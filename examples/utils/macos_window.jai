create_window_metal :: (width: int, height: int, window_name: string, window_x := -1, window_y := -1, parent: Window_Type = null, background_color_rgb := DEFAULT_WINDOW_CREATION_COLOR, wanted_msaa := DEFAULT_MSAA) -> *NSWindow {
    if !application_initialized init_mac_app();

    // On MacOS, window dimensions are specified in points, not pixels.
    // To be consistent with our other APIs, we assume width and height to be in pixels
    // and convert them to points here. :MacHighResDisplays:
    target_screen := NSScreen.mainScreen();
    pixels_to_points_factor := cast(CGFloat) 1 / NSScreen.backingScaleFactor(target_screen);
    target_frame: NSRect = ---;
    target_frame.origin = .{ xx window_x * pixels_to_points_factor, xx window_y * pixels_to_points_factor };
    target_frame.size = .{ xx width * pixels_to_points_factor, xx height * pixels_to_points_factor };

    window := NSWindow.initWithContentRect(objc_alloc(NSWindow), target_frame,
                NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable, NSBackingStoreBuffered, NO, target_screen);


    // hmm... maybe it would be better if this wasnt kept in the autoreleasepool ?
    autorelease(window);
    NSWindow.setReleasedWhenClosed(window, NO);

    NSWindow.setTitle(window, window_name);

    #if #exists(context._macos_create_window_delegate) { // :DecoupleWindowCreationAndInput:
        wd := context._macos_create_window_delegate();
        NSWindow.setDelegate(window, wd);
    }

    NSWindow.setCollectionBehavior(window, NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorManaged);
    NSWindow.makeKeyAndOrderFront(window, null);

    {
        view := objc_init(objc_alloc(NSView));

        NSView.setWantsLayer(view, YES);
        autorelease(view);

       	metal_layer := objc_init(objc_alloc(CAMetalLayer));
        autorelease(metal_layer);

	    ns_view_set_layer(view, cast(*CALayer) metal_layer);

	    NSWindow.setContentView(window, xx view);
        NSWindow.makeFirstResponder(window, view);
    }

    // @ToDo: Centering the window makes it more presentable, but is obviously
    // in direct conflict with params window_x and window_y.
    if window_x == -1 && window_y == -1 {
        NSWindow.center(window);
    }

    return window;
}

#scope_file

DEFAULT_WINDOW_CREATION_COLOR :: float.[.15,.15,.2];
DEFAULT_MSAA :: 1;

ns_view_set_layer :: (self: *NSView, layer: *CALayer) {
    func: (*NSView, Selector, *CALayer) -> void #c_call;
    func = xx objc_msgSend;
    func(self, sel_registerName("setLayer:"), layer);
}

#import "Objective_C";
#import "Objective_C/AppKit";
#import "Metal";
#import "Window_Creation"(DEFAULT_MSAA = DEFAULT_MSAA);
