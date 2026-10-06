// Private but long-stable macOS functions. There is no public API that maps an AX window element to its
// CGWindowID, identifies which native Space (Desktop) is visible, or tells which Space a window belongs to.
// Declared in C so Swift calls them with the C calling convention.
#import <ApplicationServices/ApplicationServices.h>

CF_ASSUME_NONNULL_BEGIN

typedef int CGSConnectionID;

/// HIServices: maps an Accessibility window element to its CGWindowID.
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

// SkyLight, read-only.
CGSConnectionID CGSMainConnectionID(void);
uint64_t CGSGetActiveSpace(CGSConnectionID connection);
uint64_t CGSManagedDisplayGetCurrentSpace(CGSConnectionID connection, CFStringRef displayUUID);
CFArrayRef _Nullable CGSCopySpacesForWindows(CGSConnectionID connection, int mask, CFArrayRef windowIDs) CF_RETURNS_RETAINED;

CFArrayRef _Nullable MomentumCopyManagedDisplaySpaces(CGSConnectionID connection) CF_RETURNS_RETAINED;

/// Submits a native move if the private operation is available. Does not imply completion.
BOOL MomentumRequestNativeSpaceMove(CGWindowID windowID, uint64_t spaceID);

CF_ASSUME_NONNULL_END
