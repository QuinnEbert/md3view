#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "PK3Archive.h"
#import "MD3PlayerModel.h"
#import "ModelView.h"
#import "ModelRenderer.h"
#import "TextureCache.h"
#import "AnimationConfig.h"
#import "MD3Types.h"

// ============================================================
// AppDelegate
// ============================================================

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation AppDelegate {
    NSWindow *_window;
    NSSplitView *_splitView;
    NSTableView *_tableView;
    ModelView *_modelView;
    NSScrollView *_scrollView;

    // Skin selection
    NSPopUpButton *_skinPopup;

    // Animation controls
    NSPopUpButton *_torsoPopup;
    NSPopUpButton *_legsPopup;
    NSButton *_playPauseButton;
    NSSlider *_torsoSlider;
    NSSlider *_legsSlider;
    NSTextField *_torsoFrameLabel;
    NSTextField *_legsFrameLabel;
    NSButton *_stepBackButton;
    NSButton *_stepForwardButton;
    NSSlider *_gammaSlider;
    NSTextField *_gammaLabel;
    NSView *_controlsPanel;
    NSTimer *_uiTimer;

    PK3Archive *_archive;
    NSArray<NSString *> *_playerModels;
    MD3PlayerModel *_currentModel;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self createMenu];
    [self createWindow];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)createMenu {
    NSMenu *menuBar = [NSMenu new];

    // App menu
    NSMenuItem *appMenuItem = [NSMenuItem new];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"About MD3View" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit MD3View" action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    [menuBar addItem:appMenuItem];

    // File menu
    NSMenuItem *fileMenuItem = [NSMenuItem new];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open PK3..." action:@selector(openPK3:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Save Screenshot..." action:@selector(saveScreenshot:) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Save Render..." action:@selector(saveRender:) keyEquivalent:@"S"];
    [fileMenuItem setSubmenu:fileMenu];
    [menuBar addItem:fileMenuItem];

    // Edit menu (standard for copy/paste etc)
    NSMenuItem *editMenuItem = [NSMenuItem new];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenuItem setSubmenu:editMenu];
    [menuBar addItem:editMenuItem];

    [NSApp setMainMenu:menuBar];
}

- (void)createWindow {
    NSRect frame = NSMakeRect(100, 100, 1024, 768);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled |
                                                    NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskMiniaturizable |
                                                    NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"MD3View"];
    [_window setMinSize:NSMakeSize(640, 480)];

    // Split view: sidebar | (GL view + controls)
    _splitView = [[NSSplitView alloc] initWithFrame:[[_window contentView] bounds]];
    [_splitView setDividerStyle:NSSplitViewDividerStyleThin];
    [_splitView setVertical:YES];
    [_splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Sidebar (model list)
    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 768)];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"ModelName"];
    [col setTitle:@"Player Models"];
    [col setMinWidth:100];
    [_tableView addTableColumn:col];
    [_tableView setHeaderView:nil];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setRowHeight:24];
    [_scrollView setDocumentView:_tableView];

    // Right panel: GL view on top, controls on bottom
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 768)];
    [rightPanel setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Controls panel (bottom)
    CGFloat controlsHeight = 150;
    _controlsPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, controlsHeight)];
    [_controlsPanel setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self setupControlsPanel];

    // Model view (fills remaining space above controls)
    _modelView = [[ModelView alloc] initWithFrame:NSMakeRect(0, controlsHeight, 800, 768 - controlsHeight)];
    [_modelView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    [rightPanel addSubview:_modelView];
    [rightPanel addSubview:_controlsPanel];

    [_splitView addSubview:_scrollView];
    [_splitView addSubview:rightPanel];
    [_splitView setPosition:200 ofDividerAtIndex:0];

    [[_window contentView] addSubview:_splitView];
    [_window makeKeyAndOrderFront:nil];

    [_modelView startDisplayLink];

    // UI timer for updating frame labels/sliders
    _uiTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 target:self
                                              selector:@selector(updateUIControls)
                                              userInfo:nil repeats:YES];
}

- (void)setupControlsPanel {
    CGFloat y = 110;
    CGFloat leftMargin = 10;

    // Row 0: Skin selection
    NSTextField *skinLabel = [NSTextField labelWithString:@"Skin:"];
    [skinLabel setFrame:NSMakeRect(leftMargin, y, 45, 20)];
    [_controlsPanel addSubview:skinLabel];

    _skinPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 50, y, 180, 24) pullsDown:NO];
    [_skinPopup setTarget:self];
    [_skinPopup setAction:@selector(skinChanged:)];
    [_controlsPanel addSubview:_skinPopup];

    y -= 30;

    // Row 1: Torso animation popup + frame info
    NSTextField *torsoLabel = [NSTextField labelWithString:@"Torso:"];
    [torsoLabel setFrame:NSMakeRect(leftMargin, y, 45, 20)];
    [_controlsPanel addSubview:torsoLabel];

    _torsoPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 50, y, 180, 24) pullsDown:NO];
    [_torsoPopup setTarget:self];
    [_torsoPopup setAction:@selector(torsoAnimChanged:)];
    [_controlsPanel addSubview:_torsoPopup];

    _torsoSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(leftMargin + 240, y, 200, 20)];
    [_torsoSlider setMinValue:0];
    [_torsoSlider setMaxValue:1];
    [_torsoSlider setTarget:self];
    [_torsoSlider setAction:@selector(torsoSliderChanged:)];
    [_torsoSlider setAutoresizingMask:NSViewWidthSizable];
    [_controlsPanel addSubview:_torsoSlider];

    _torsoFrameLabel = [NSTextField labelWithString:@"Frame 0/0"];
    [_torsoFrameLabel setFrame:NSMakeRect(leftMargin + 450, y, 120, 20)];
    [_torsoFrameLabel setAutoresizingMask:NSViewMinXMargin];
    [_controlsPanel addSubview:_torsoFrameLabel];

    y -= 30;

    // Row 2: Legs animation popup + frame info
    NSTextField *legsLabel = [NSTextField labelWithString:@"Legs:"];
    [legsLabel setFrame:NSMakeRect(leftMargin, y, 45, 20)];
    [_controlsPanel addSubview:legsLabel];

    _legsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 50, y, 180, 24) pullsDown:NO];
    [_legsPopup setTarget:self];
    [_legsPopup setAction:@selector(legsAnimChanged:)];
    [_controlsPanel addSubview:_legsPopup];

    _legsSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(leftMargin + 240, y, 200, 20)];
    [_legsSlider setMinValue:0];
    [_legsSlider setMaxValue:1];
    [_legsSlider setTarget:self];
    [_legsSlider setAction:@selector(legsSliderChanged:)];
    [_legsSlider setAutoresizingMask:NSViewWidthSizable];
    [_controlsPanel addSubview:_legsSlider];

    _legsFrameLabel = [NSTextField labelWithString:@"Frame 0/0"];
    [_legsFrameLabel setFrame:NSMakeRect(leftMargin + 450, y, 120, 20)];
    [_legsFrameLabel setAutoresizingMask:NSViewMinXMargin];
    [_controlsPanel addSubview:_legsFrameLabel];

    y -= 30;

    // Row 3: Play/Pause + Step buttons
    _playPauseButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 80, 24)];
    [_playPauseButton setTitle:@"Pause"];
    [_playPauseButton setBezelStyle:NSBezelStyleRounded];
    [_playPauseButton setTarget:self];
    [_playPauseButton setAction:@selector(togglePlayPause:)];
    [_controlsPanel addSubview:_playPauseButton];

    _stepBackButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 90, y, 40, 24)];
    [_stepBackButton setTitle:@"<"];
    [_stepBackButton setBezelStyle:NSBezelStyleRounded];
    [_stepBackButton setTarget:self];
    [_stepBackButton setAction:@selector(stepBack:)];
    [_controlsPanel addSubview:_stepBackButton];

    _stepForwardButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 135, y, 40, 24)];
    [_stepForwardButton setTitle:@">"];
    [_stepForwardButton setBezelStyle:NSBezelStyleRounded];
    [_stepForwardButton setTarget:self];
    [_stepForwardButton setAction:@selector(stepForward:)];
    [_controlsPanel addSubview:_stepForwardButton];

    // Gamma slider on the same row, right side
    NSTextField *gammaTitle = [NSTextField labelWithString:@"Gamma:"];
    [gammaTitle setFrame:NSMakeRect(leftMargin + 200, y, 50, 20)];
    [_controlsPanel addSubview:gammaTitle];

    _gammaSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(leftMargin + 255, y, 140, 20)];
    [_gammaSlider setMinValue:0.3];
    [_gammaSlider setMaxValue:3.0];
    [_gammaSlider setFloatValue:1.0];
    [_gammaSlider setTarget:self];
    [_gammaSlider setAction:@selector(gammaChanged:)];
    [_gammaSlider setAutoresizingMask:NSViewWidthSizable];
    [_controlsPanel addSubview:_gammaSlider];

    _gammaLabel = [NSTextField labelWithString:@"1.00"];
    [_gammaLabel setFrame:NSMakeRect(leftMargin + 400, y, 50, 20)];
    [_gammaLabel setAutoresizingMask:NSViewMinXMargin];
    [_controlsPanel addSubview:_gammaLabel];

    [self populateAnimPopups];
}

- (void)populateAnimPopups {
    [_torsoPopup removeAllItems];
    [_legsPopup removeAllItems];

    for (int i = 0; i < MAX_ANIMATIONS; i++) {
        NSString *name = [NSString stringWithUTF8String:AnimationNames[i]];
        [_torsoPopup addItemWithTitle:name];
        [_legsPopup addItemWithTitle:name];
    }

    [_torsoPopup selectItemAtIndex:TORSO_STAND];
    [_legsPopup selectItemAtIndex:LEGS_IDLE];
}

// ============================================================
// Animation control actions
// ============================================================

- (void)skinChanged:(id)sender {
    if (!_currentModel) return;
    NSString *skinName = [[_skinPopup selectedItem] title];
    [_currentModel selectSkin:skinName];
    // Flush texture cache so new skin textures load
    [[_modelView openGLContext] makeCurrentContext];
    [_modelView.textureCache flush];
    [_modelView setNeedsDisplay:YES];
}

- (void)gammaChanged:(id)sender {
    float gamma = [_gammaSlider floatValue];
    _modelView.gamma = gamma;
    [_gammaLabel setStringValue:[NSString stringWithFormat:@"%.2f", gamma]];
    [_modelView setNeedsDisplay:YES];
}

- (void)torsoAnimChanged:(id)sender {
    if (!_currentModel) return;
    AnimNumber anim = (AnimNumber)[_torsoPopup indexOfSelectedItem];
    [_currentModel setTorsoAnimation:anim];
    int numFrames = [_currentModel torsoNumFrames];
    [_torsoSlider setMaxValue:numFrames > 0 ? numFrames - 1 : 0];
    [_torsoSlider setIntValue:0];
}

- (void)legsAnimChanged:(id)sender {
    if (!_currentModel) return;
    AnimNumber anim = (AnimNumber)[_legsPopup indexOfSelectedItem];
    [_currentModel setLegsAnimation:anim];
    int numFrames = [_currentModel legsNumFrames];
    [_legsSlider setMaxValue:numFrames > 0 ? numFrames - 1 : 0];
    [_legsSlider setIntValue:0];
}

- (void)togglePlayPause:(id)sender {
    if (!_currentModel) return;
    _currentModel.playing = !_currentModel.playing;
    [_playPauseButton setTitle:_currentModel.playing ? @"Pause" : @"Play"];
}

- (void)stepBack:(id)sender {
    if (!_currentModel || _currentModel.playing) return;
    [_currentModel stepFrame:-1];
    [_modelView setNeedsDisplay:YES];
}

- (void)stepForward:(id)sender {
    if (!_currentModel || _currentModel.playing) return;
    [_currentModel stepFrame:1];
    [_modelView setNeedsDisplay:YES];
}

- (void)torsoSliderChanged:(id)sender {
    if (!_currentModel || _currentModel.playing) return;
    [_currentModel scrubTorsoToFrame:[_torsoSlider intValue]];
    [_modelView setNeedsDisplay:YES];
}

- (void)legsSliderChanged:(id)sender {
    if (!_currentModel || _currentModel.playing) return;
    [_currentModel scrubLegsToFrame:[_legsSlider intValue]];
    [_modelView setNeedsDisplay:YES];
}

- (void)updateUIControls {
    if (!_currentModel) return;
    int torsoFrame = [_currentModel torsoCurrentFrame];
    int torsoTotal = [_currentModel torsoNumFrames];
    int legsFrame = [_currentModel legsCurrentFrame];
    int legsTotal = [_currentModel legsNumFrames];

    [_torsoFrameLabel setStringValue:[NSString stringWithFormat:@"Frame %d / %d", torsoFrame, torsoTotal]];
    [_legsFrameLabel setStringValue:[NSString stringWithFormat:@"Frame %d / %d", legsFrame, legsTotal]];

    if (_currentModel.playing) {
        if (torsoTotal > 0) [_torsoSlider setMaxValue:torsoTotal - 1];
        [_torsoSlider setIntValue:torsoFrame];
        if (legsTotal > 0) [_legsSlider setMaxValue:legsTotal - 1];
        [_legsSlider setIntValue:legsFrame];
    }
}

// ============================================================
// Table view (model list)
// ============================================================

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _playerModels.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"Cell" owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = @"Cell";
    }
    NSString *fullPath = _playerModels[row];
    cell.stringValue = [fullPath lastPathComponent];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [_tableView selectedRow];
    if (row < 0 || row >= (NSInteger)_playerModels.count) return;

    NSString *modelPath = _playerModels[row];
    [self loadPlayerModel:modelPath];
}

// ============================================================
// File actions
// ============================================================

- (void)openPK3:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowedContentTypes:@[[UTType typeWithFilenameExtension:@"pk3"]]];
    [panel setAllowsMultipleSelection:NO];
    [panel setTitle:@"Open PK3 File"];

    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSString *path = [[panel URL] path];
        [self loadArchive:path];
    }];
}

- (void)loadArchive:(NSString *)path {
    _archive = [[PK3Archive alloc] initWithPath:path];
    if (!_archive) {
        NSAlert *alert = [NSAlert new];
        [alert setMessageText:@"Failed to open PK3 file"];
        [alert runModal];
        return;
    }

    _playerModels = [_archive playerModelPaths];
    [_tableView reloadData];

    [_window setTitle:[NSString stringWithFormat:@"MD3View - %@", [path lastPathComponent]]];

    // Auto-select first model if available
    if (_playerModels.count > 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

- (void)loadPlayerModel:(NSString *)modelPath {
    [[_modelView openGLContext] makeCurrentContext];

    // Flush old textures
    [_modelView.textureCache flush];

    TextureCache *texCache = [[TextureCache alloc] initWithArchive:_archive];
    _modelView.textureCache = texCache;

    MD3PlayerModel *model = [[MD3PlayerModel alloc] initWithArchive:_archive modelPath:modelPath];
    if (!model) {
        NSLog(@"Failed to load player model: %@", modelPath);
        return;
    }

    _currentModel = model;
    _modelView.playerModel = model;

    // Update skin popup
    [_skinPopup removeAllItems];
    for (NSString *skin in [model availableSkins]) {
        [_skinPopup addItemWithTitle:skin];
    }
    if ([model currentSkin]) {
        [_skinPopup selectItemWithTitle:[model currentSkin]];
    }

    // Update animation controls
    [_torsoPopup selectItemAtIndex:TORSO_STAND];
    [_legsPopup selectItemAtIndex:LEGS_IDLE];
    [_playPauseButton setTitle:@"Pause"];

    int torsoFrames = [_currentModel torsoNumFrames];
    int legsFrames = [_currentModel legsNumFrames];
    [_torsoSlider setMaxValue:torsoFrames > 0 ? torsoFrames - 1 : 0];
    [_legsSlider setMaxValue:legsFrames > 0 ? legsFrames - 1 : 0];

    [_modelView setNeedsDisplay:YES];
}

- (void)saveScreenshot:(id)sender {
    if (!_currentModel) return;

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedContentTypes:@[UTTypePNG]];
    [panel setNameFieldStringValue:@"screenshot.png"];

    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;

        NSImage *image = [self->_modelView captureScreenshotWithScale:2];
        if (!image) return;

        NSBitmapImageRep *rep = (NSBitmapImageRep *)[[image representations] firstObject];
        NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [pngData writeToURL:[panel URL] atomically:YES];
    }];
}

- (void)saveRender:(id)sender {
    if (!_currentModel) return;

    // Build resolution picker dialog
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Save Render"];
    [alert setInformativeText:@"Choose a resolution or enter custom dimensions:"];
    [alert addButtonWithTitle:@"Render"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];

    // Preset popup
    NSPopUpButton *presetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 70, 300, 24) pullsDown:NO];
    [presetPopup addItemWithTitle:@"1080p (1920x1080)"];
    [presetPopup addItemWithTitle:@"1440p (2560x1440)"];
    [presetPopup addItemWithTitle:@"4K (3840x2160)"];
    [presetPopup addItemWithTitle:@"4K Portrait (2160x3840)"];
    [presetPopup addItemWithTitle:@"Square 2K (2048x2048)"];
    [presetPopup addItemWithTitle:@"Square 4K (4096x4096)"];
    [presetPopup addItemWithTitle:@"Custom"];
    [accessory addSubview:presetPopup];

    static const int presetWidths[]  = {1920, 2560, 3840, 2160, 2048, 4096};
    static const int presetHeights[] = {1080, 1440, 2160, 3840, 2048, 4096};

    // Width / Height fields
    NSTextField *wLabel = [NSTextField labelWithString:@"Width:"];
    [wLabel setFrame:NSMakeRect(0, 35, 45, 20)];
    [accessory addSubview:wLabel];

    NSTextField *wField = [[NSTextField alloc] initWithFrame:NSMakeRect(50, 35, 80, 22)];
    [wField setIntValue:3840];
    [accessory addSubview:wField];

    NSTextField *hLabel = [NSTextField labelWithString:@"Height:"];
    [hLabel setFrame:NSMakeRect(150, 35, 50, 20)];
    [accessory addSubview:hLabel];

    NSTextField *hField = [[NSTextField alloc] initWithFrame:NSMakeRect(205, 35, 80, 22)];
    [hField setIntValue:2160];
    [accessory addSubview:hField];

    // Wire preset to update fields
    __block NSTextField *wFieldRef = wField;
    __block NSTextField *hFieldRef = hField;
    presetPopup.target = nil; // We'll read on OK

    NSTextField *note = [NSTextField labelWithString:@"Model will be auto-framed to fill the output."];
    [note setFrame:NSMakeRect(0, 5, 300, 20)];
    [note setTextColor:[NSColor secondaryLabelColor]];
    [note setFont:[NSFont systemFontOfSize:11]];
    [accessory addSubview:note];

    [alert setAccessoryView:accessory];

    // Update fields when preset changes
    [presetPopup setTarget:self];
    [presetPopup setAction:@selector(_renderPresetChanged:)];
    // Stash references for the action — use objc_setAssociatedObject or just read in completion
    // Simpler: just read the popup index + fields when user clicks Render

    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        int idx = (int)[presetPopup indexOfSelectedItem];
        int renderW, renderH;
        if (idx < 6) {
            renderW = presetWidths[idx];
            renderH = presetHeights[idx];
        } else {
            renderW = [wFieldRef intValue];
            renderH = [hFieldRef intValue];
        }

        // Clamp to sane values
        if (renderW < 64) renderW = 64;
        if (renderH < 64) renderH = 64;
        if (renderW > 8192) renderW = 8192;
        if (renderH > 8192) renderH = 8192;

        // Ask where to save
        NSSavePanel *savePanel = [NSSavePanel savePanel];
        [savePanel setAllowedContentTypes:@[UTTypePNG]];
        [savePanel setNameFieldStringValue:[NSString stringWithFormat:@"render_%dx%d.png", renderW, renderH]];

        [savePanel beginSheetModalForWindow:self->_window completionHandler:^(NSModalResponse saveResult) {
            if (saveResult != NSModalResponseOK) return;

            NSImage *image = [self->_modelView captureRenderWithWidth:renderW height:renderH];
            if (!image) return;

            NSBitmapImageRep *rep = (NSBitmapImageRep *)[[image representations] firstObject];
            NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [pngData writeToURL:[savePanel URL] atomically:YES];
        }];
    }];
}

- (void)_renderPresetChanged:(NSPopUpButton *)popup {
    // Find the width/height fields — siblings in the accessory view
    NSView *container = [popup superview];
    NSTextField *wField = nil, *hField = nil;
    for (NSView *sub in [container subviews]) {
        if ([sub isKindOfClass:[NSTextField class]] && [(NSTextField *)sub isEditable]) {
            if (!wField) wField = (NSTextField *)sub;
            else hField = (NSTextField *)sub;
        }
    }
    if (!wField || !hField) return;

    static const int presetWidths[]  = {1920, 2560, 3840, 2160, 2048, 4096};
    static const int presetHeights[] = {1080, 1440, 2160, 3840, 2048, 4096};
    int idx = (int)[popup indexOfSelectedItem];
    if (idx < 6) {
        [wField setIntValue:presetWidths[idx]];
        [hField setIntValue:presetHeights[idx]];
    }
}

@end

// ============================================================
// Main entry point
// ============================================================

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        AppDelegate *delegate = [AppDelegate new];
        [app setDelegate:delegate];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
