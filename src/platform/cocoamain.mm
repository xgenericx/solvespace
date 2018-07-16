//-----------------------------------------------------------------------------
// Our main() function, and Cocoa-specific stuff to set up our windows and
// otherwise handle our interface to the operating system. Everything
// outside platform/... should be standard C++ and OpenGL.
//
// Copyright 2015 <whitequark@whitequark.org>
//-----------------------------------------------------------------------------
#include <mach/mach.h>
#include <mach/clock.h>
#import  <AppKit/AppKit.h>

#include "solvespace.h"

using SolveSpace::dbp;

/* Utility functions */

static NSString* Wrap(const std::string &s) {
    return [NSString stringWithUTF8String:s.c_str()];
}

/* Save/load */

bool SolveSpace::GetOpenFile(Platform::Path *filename, const std::string &defExtension,
                             const FileFilter ssFilters[]) {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    NSMutableArray *filters = [[NSMutableArray alloc] init];
    for(const FileFilter *ssFilter = ssFilters; ssFilter->name; ssFilter++) {
        for(const char *const *ssPattern = ssFilter->patterns; *ssPattern; ssPattern++) {
            [filters addObject:[NSString stringWithUTF8String:*ssPattern]];
        }
    }
    [filters removeObjectIdenticalTo:@"*"];
    [panel setAllowedFileTypes:filters];

    if([panel runModal] == NSFileHandlingPanelOKButton) {
        *filename = Platform::Path::From(
            [[NSFileManager defaultManager]
                fileSystemRepresentationWithPath:[[panel URL] path]]);
        return true;
    } else {
        return false;
    }
}

@interface SaveFormatController : NSViewController
@property NSSavePanel *panel;
@property NSArray *extensions;
@property (nonatomic) IBOutlet NSPopUpButton *button;
@property (nonatomic) NSInteger index;
@end

@implementation SaveFormatController
@synthesize panel, extensions, button, index;
- (void)setIndex:(NSInteger)newIndex {
    self->index = newIndex;
    NSString *extension = [extensions objectAtIndex:newIndex];
    if(![extension isEqual:@"*"]) {
        NSString *filename = [panel nameFieldStringValue];
        NSString *basename = [[filename componentsSeparatedByString:@"."] objectAtIndex:0];
        [panel setNameFieldStringValue:[basename stringByAppendingPathExtension:extension]];
    }
}
@end

bool SolveSpace::GetSaveFile(Platform::Path *filename, const std::string &defExtension,
                             const FileFilter ssFilters[]) {
    NSSavePanel *panel = [NSSavePanel savePanel];

    SaveFormatController *controller =
        [[SaveFormatController alloc] initWithNibName:@"SaveFormatAccessory" bundle:nil];
    [controller setPanel:panel];
    [panel setAccessoryView:[controller view]];

    NSMutableArray *extensions = [[NSMutableArray alloc] init];

    NSPopUpButton *button = [controller button];
    [button removeAllItems];
    for(const FileFilter *ssFilter = ssFilters; ssFilter->name; ssFilter++) {
        std::string desc;
        for(const char *const *ssPattern = ssFilter->patterns; *ssPattern; ssPattern++) {
            if(desc == "") {
                desc = *ssPattern;
            } else {
                desc += ", ";
                desc += *ssPattern;
            }
        }
        std::string title = Translate(ssFilter->name) + " (" + desc + ")";
        [button addItemWithTitle:Wrap(title)];
        [extensions addObject:[NSString stringWithUTF8String:ssFilter->patterns[0]]];
    }
    [panel setAllowedFileTypes:extensions];
    [controller setExtensions:extensions];

    int extensionIndex = 0;
    if(defExtension != "") {
        extensionIndex = [extensions indexOfObject:Wrap(defExtension)];
        if(extensionIndex == -1) {
            extensionIndex = 0;
        }
    }
    [button selectItemAtIndex:extensionIndex];

    if(filename->IsEmpty()) {
        [panel setNameFieldStringValue:
            [Wrap(_("untitled"))
                stringByAppendingPathExtension:[extensions objectAtIndex:extensionIndex]]];
    } else {
        [panel setDirectoryURL:
            [NSURL fileURLWithPath:Wrap(filename->Parent().raw)
                   isDirectory:NO]];
        [panel setNameFieldStringValue:
            [Wrap(filename->FileStem())
                stringByAppendingPathExtension:[extensions objectAtIndex:extensionIndex]]];
    }

    if([panel runModal] == NSFileHandlingPanelOKButton) {
        *filename = Platform::Path::From(
            [[NSFileManager defaultManager]
                fileSystemRepresentationWithPath:[[panel URL] path]]);
        return true;
    } else {
        return false;
    }
}

SolveSpace::DialogChoice SolveSpace::SaveFileYesNoCancel() {
    NSAlert *alert = [[NSAlert alloc] init];
    if(!SolveSpace::SS.saveFile.IsEmpty()) {
        [alert setMessageText:
            [[@"Do you want to save the changes you made to the sketch “"
             stringByAppendingString:
                [Wrap(SolveSpace::SS.saveFile.raw)
                    stringByAbbreviatingWithTildeInPath]]
             stringByAppendingString:@"”?"]];
    } else {
        [alert setMessageText:
            Wrap(_("Do you want to save the changes you made to the new sketch?"))];
    }
    [alert setInformativeText:Wrap(_("Your changes will be lost if you don't save them."))];
    [alert addButtonWithTitle:Wrap(C_("button", "Save"))];
    [alert addButtonWithTitle:Wrap(C_("button", "Cancel"))];
    [alert addButtonWithTitle:Wrap(C_("button", "Don't Save"))];
    switch([alert runModal]) {
        case NSAlertFirstButtonReturn:
        return DIALOG_YES;
        case NSAlertSecondButtonReturn:
        default:
        return DIALOG_CANCEL;
        case NSAlertThirdButtonReturn:
        return DIALOG_NO;
    }
}

SolveSpace::DialogChoice SolveSpace::LoadAutosaveYesNo() {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:
        Wrap(_("An autosave file is available for this project."))];
    [alert setInformativeText:
        Wrap(_("Do you want to load the autosave file instead?"))];
    [alert addButtonWithTitle:Wrap(C_("button", "Load"))];
    [alert addButtonWithTitle:Wrap(C_("button", "Don't Load"))];
    switch([alert runModal]) {
        case NSAlertFirstButtonReturn:
        return DIALOG_YES;
        case NSAlertSecondButtonReturn:
        default:
        return DIALOG_NO;
    }
}

SolveSpace::DialogChoice SolveSpace::LocateImportedFileYesNoCancel(
                            const Platform::Path &filename, bool canCancel) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:
        Wrap("The linked file “" + filename.raw + "” is not present.")];
    [alert setInformativeText:
        Wrap(_("Do you want to locate it manually?\n"
               "If you select “No”, any geometry that depends on "
               "the missing file will be removed."))];
    [alert addButtonWithTitle:Wrap(C_("button", "Yes"))];
    if(canCancel)
        [alert addButtonWithTitle:Wrap(C_("button", "Cancel"))];
    [alert addButtonWithTitle:Wrap(C_("button", "No"))];
    switch([alert runModal]) {
        case NSAlertFirstButtonReturn:
        return DIALOG_YES;
        case NSAlertSecondButtonReturn:
        default:
        if(canCancel)
            return DIALOG_CANCEL;
        /* fallthrough */
        case NSAlertThirdButtonReturn:
        return DIALOG_NO;
    }
}

/* Miscellanea */

void SolveSpace::DoMessageBox(const char *str, int rows, int cols, bool error) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:(error ? NSWarningAlertStyle : NSInformationalAlertStyle)];
    [alert addButtonWithTitle:Wrap(C_("button", "OK"))];

    /* do some additional formatting of the message;
       these are heuristics, but they are made failsafe and lead to nice results. */
    NSString *input = [NSString stringWithUTF8String:str];
    NSRange dot = [input rangeOfCharacterFromSet:
        [NSCharacterSet characterSetWithCharactersInString:@".:"]];
    if(dot.location != NSNotFound) {
        [alert setMessageText:[[input substringToIndex:dot.location + 1]
            stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
        [alert setInformativeText:
            [[input substringFromIndex:dot.location + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]];
    } else {
        [alert setMessageText:[input
            stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    }

    [alert runModal];
}

void SolveSpace::OpenWebsite(const char *url) {
    [[NSWorkspace sharedWorkspace] openURL:
        [NSURL URLWithString:[NSString stringWithUTF8String:url]]];
}

std::vector<SolveSpace::Platform::Path> SolveSpace::GetFontFiles() {
    std::vector<SolveSpace::Platform::Path> fonts;

    NSArray *fontNames = [[NSFontManager sharedFontManager] availableFonts];
    for(NSString *fontName in fontNames) {
        CTFontDescriptorRef fontRef =
            CTFontDescriptorCreateWithNameAndSize ((__bridge CFStringRef)fontName, 10.0);
        CFURLRef url = (CFURLRef)CTFontDescriptorCopyAttribute(fontRef, kCTFontURLAttribute);
        NSString *fontPath = [NSString stringWithString:[(NSURL *)CFBridgingRelease(url) path]];
        fonts.push_back(
            Platform::Path::From([[NSFileManager defaultManager]
                fileSystemRepresentationWithPath:fontPath]));
    }

    return fonts;
}

/* Application lifecycle */

@interface ApplicationDelegate : NSObject<NSApplicationDelegate>
- (IBAction)preferences:(id)sender;
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
@end

@implementation ApplicationDelegate
- (IBAction)preferences:(id)sender {
    SolveSpace::SS.TW.GoToScreen(SolveSpace::TextWindow::Screen::CONFIGURATION);
    SolveSpace::SS.ScheduleShowTW();
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
    SolveSpace::Platform::Path path = SolveSpace::Platform::Path::From([filename UTF8String]);
    return SolveSpace::SS.Load(path.Expand(/*fromCurrentDirectory=*/true));
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    [[[NSApp mainWindow] delegate] windowShouldClose:nil];
    return NSTerminateCancel;
}

- (void)applicationTerminatePrompt {
    SolveSpace::SS.MenuFile(SolveSpace::Command::EXIT);
}
@end

/*
 * Normally we would just link to the 3DconnexionClient framework.
 * We don't want to (are not allowed to) distribute the official
 * framework, so we're trying to use the one installed on the users
 * computer. There are some different versions of the framework,
 * the official one and re-implementations using an open source driver
 * for older devices (spacenav-plus). So weak-linking isn't an option,
 * either. The only remaining way is using CFBundle to dynamically
 * load the library at runtime, and also detect its availability.
 *
 * We're also defining everything needed from the 3DconnexionClientAPI,
 * so we're not depending on the API headers.
 */

#pragma pack(push,2)

enum {
    kConnexionClientModeTakeOver = 1,
    kConnexionClientModePlugin = 2
};

#define kConnexionMsgDeviceState '3dSR'
#define kConnexionMaskButtons 0x00FF
#define kConnexionMaskAxis 0x3F00

typedef struct {
    uint16_t version;
    uint16_t client;
    uint16_t command;
    int16_t param;
    int32_t value;
    UInt64 time;
    uint8_t report[8];
    uint16_t buttons8;
    int16_t axis[6];
    uint16_t address;
    uint32_t buttons;
} ConnexionDeviceState, *ConnexionDeviceStatePtr;

#pragma pack(pop)

typedef void (*ConnexionAddedHandlerProc)(io_connect_t);
typedef void (*ConnexionRemovedHandlerProc)(io_connect_t);
typedef void (*ConnexionMessageHandlerProc)(io_connect_t, natural_t, void *);

typedef OSErr (*InstallConnexionHandlersProc)(ConnexionMessageHandlerProc, ConnexionAddedHandlerProc, ConnexionRemovedHandlerProc);
typedef void (*CleanupConnexionHandlersProc)(void);
typedef UInt16 (*RegisterConnexionClientProc)(UInt32, UInt8 *, UInt16, UInt32);
typedef void (*UnregisterConnexionClientProc)(UInt16);

static BOOL connexionShiftIsDown = NO;
static UInt16 connexionClient = 0;
static UInt32 connexionSignature = 'SoSp';
static UInt8 *connexionName = (UInt8 *)"\x10SolveSpace";
static CFBundleRef spaceBundle = NULL;
static InstallConnexionHandlersProc installConnexionHandlers = NULL;
static CleanupConnexionHandlersProc cleanupConnexionHandlers = NULL;
static RegisterConnexionClientProc registerConnexionClient = NULL;
static UnregisterConnexionClientProc unregisterConnexionClient = NULL;

static void connexionAdded(io_connect_t con) {}
static void connexionRemoved(io_connect_t con) {}
static void connexionMessage(io_connect_t con, natural_t type, void *arg) {
    if (type != kConnexionMsgDeviceState) {
        return;
    }

    ConnexionDeviceState *device = (ConnexionDeviceState *)arg;

    dispatch_async(dispatch_get_main_queue(), ^(void){
        SolveSpace::SS.GW.SpaceNavigatorMoved(
            (double)device->axis[0] * -0.25,
            (double)device->axis[1] * -0.25,
            (double)device->axis[2] * 0.25,
            (double)device->axis[3] * -0.0005,
            (double)device->axis[4] * -0.0005,
            (double)device->axis[5] * -0.0005,
            (connexionShiftIsDown == YES) ? 1 : 0
        );
    });
}

static void connexionInit() {
    NSString *bundlePath = @"/Library/Frameworks/3DconnexionClient.framework";
    NSURL *bundleURL = [NSURL fileURLWithPath:bundlePath];
    spaceBundle = CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)bundleURL);

    // Don't continue if no Spacemouse driver is installed on this machine
    if (spaceBundle == NULL) {
        return;
    }

    installConnexionHandlers = (InstallConnexionHandlersProc)
                CFBundleGetFunctionPointerForName(spaceBundle,
                        CFSTR("InstallConnexionHandlers"));

    cleanupConnexionHandlers = (CleanupConnexionHandlersProc)
                CFBundleGetFunctionPointerForName(spaceBundle,
                        CFSTR("CleanupConnexionHandlers"));

    registerConnexionClient = (RegisterConnexionClientProc)
                CFBundleGetFunctionPointerForName(spaceBundle,
                        CFSTR("RegisterConnexionClient"));

    unregisterConnexionClient = (UnregisterConnexionClientProc)
                CFBundleGetFunctionPointerForName(spaceBundle,
                        CFSTR("UnregisterConnexionClient"));

    // Only continue if all required symbols have been loaded
    if ((installConnexionHandlers == NULL) || (cleanupConnexionHandlers == NULL)
            || (registerConnexionClient == NULL) || (unregisterConnexionClient == NULL)) {
        CFRelease(spaceBundle);
        spaceBundle = NULL;
        return;
    }

    installConnexionHandlers(&connexionMessage, &connexionAdded, &connexionRemoved);
    connexionClient = registerConnexionClient(connexionSignature, connexionName,
            kConnexionClientModeTakeOver, kConnexionMaskButtons | kConnexionMaskAxis);

    // Monitor modifier flags to detect Shift button state changes
    [NSEvent addLocalMonitorForEventsMatchingMask:(NSKeyDownMask | NSFlagsChangedMask)
                                          handler:^(NSEvent *event) {
        if (event.modifierFlags & NSShiftKeyMask) {
            connexionShiftIsDown = YES;
        }
        return event;
    }];

    [NSEvent addLocalMonitorForEventsMatchingMask:(NSKeyUpMask | NSFlagsChangedMask)
                                          handler:^(NSEvent *event) {
        if (!(event.modifierFlags & NSShiftKeyMask)) {
            connexionShiftIsDown = NO;
        }
        return event;
    }];
}

static void connexionClose() {
    if (spaceBundle == NULL) {
        return;
    }

    unregisterConnexionClient(connexionClient);
    cleanupConnexionHandlers();

    CFRelease(spaceBundle);
}

int main(int argc, const char *argv[]) {
    ApplicationDelegate *delegate = [[ApplicationDelegate alloc] init];
    [[NSApplication sharedApplication] setDelegate:delegate];

    [[NSBundle mainBundle] loadNibNamed:@"MainMenu" owner:nil topLevelObjects:nil];

    NSArray *languages = [NSLocale preferredLanguages];
    for(NSString *language in languages) {
        if(SolveSpace::SetLocale([language UTF8String])) break;
    }
    if([languages count] == 0) {
        SolveSpace::SetLocale("en_US");
    }

    connexionInit();
    SolveSpace::SS.Init();

    [NSApp run];

    connexionClose();
    SolveSpace::SK.Clear();
    SolveSpace::SS.Clear();

    return 0;
}
