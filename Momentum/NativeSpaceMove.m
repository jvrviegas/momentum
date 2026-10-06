#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/nlist.h>
#import <objc/message.h>
#import "Momentum-Bridging-Header.h"

// This SkyLight operation is not exported, so dlsym cannot find it. Resolve its exact
// local symbol in the loaded image, never a version-specific address or byte pattern.
// Mechanism verified against yabai's src/misc/macho_dlsym.h and src/space_manager.c.
static void *FindSkyLightSymbol(const char *name) {
    for (uint32_t image = 0; image < _dyld_image_count(); ++image) {
        const char *path = _dyld_get_image_name(image);
        if (!path || !strstr(path, "/SkyLight.framework/")) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(image);
        if (!header || header->magic != MH_MAGIC_64) return NULL;
        const uint8_t *cursor = (const uint8_t *)(header + 1);
        const uint8_t *end = cursor + header->sizeofcmds;
        const struct segment_command_64 *linkedit = NULL;
        const struct symtab_command *symtab = NULL;
        for (uint32_t index = 0; index < header->ncmds; ++index) {
            if ((size_t)(end - cursor) < sizeof(struct load_command)) return NULL;
            const struct load_command *command = (const void *)cursor;
            if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - cursor)) return NULL;
            if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *segment = (const void *)command;
                if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) linkedit = segment;
            } else if (command->cmd == LC_SYMTAB && command->cmdsize >= sizeof(struct symtab_command)) {
                symtab = (const void *)command;
            }
            cursor += command->cmdsize;
        }
        if (!linkedit || !symtab) return NULL;
        uint64_t fileEnd = linkedit->fileoff + linkedit->filesize;
        if (symtab->symoff < linkedit->fileoff || symtab->stroff < linkedit->fileoff ||
            (uint64_t)symtab->symoff + (uint64_t)symtab->nsyms * sizeof(struct nlist_64) > fileEnd ||
            (uint64_t)symtab->stroff + symtab->strsize > fileEnd) return NULL;
        intptr_t slide = _dyld_get_image_vmaddr_slide(image);
        uintptr_t base = linkedit->vmaddr + slide - linkedit->fileoff;
        const struct nlist_64 *symbols = (const void *)(base + symtab->symoff);
        const char *strings = (const void *)(base + symtab->stroff);
        for (uint32_t index = 0; index < symtab->nsyms; ++index) {
            const struct nlist_64 *symbol = &symbols[index];
            if ((symbol->n_type & N_STAB) || (symbol->n_type & N_TYPE) != N_SECT ||
                !symbol->n_value || symbol->n_un.n_strx >= symtab->strsize) continue;
            const char *candidate = strings + symbol->n_un.n_strx;
            size_t remaining = symtab->strsize - symbol->n_un.n_strx;
            if (memchr(candidate, '\0', remaining) && strcmp(candidate, name) == 0) {
                return (void *)(symbol->n_value + slide);
            }
        }
    }
    return NULL;
}

CFArrayRef MomentumCopyManagedDisplaySpaces(CGSConnectionID connection) {
    typedef CFArrayRef (*CopyDisplays)(CGSConnectionID);
    static CopyDisplays copyDisplays;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (handle) copyDisplays = (CopyDisplays)dlsym(handle, "SLSCopyManagedDisplaySpaces");
    });
    return copyDisplays ? copyDisplays(connection) : NULL;
}

typedef int64_t (*PerformOperation)(void *);

static PerformOperation NativeMoveOperation(void) {
    static PerformOperation perform;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // AppKit normally loads SkyLight already. Keep the handle for the process lifetime.
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        perform = (PerformOperation)FindSkyLightSymbol(
            "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation");
    });
    return perform;
}

BOOL MomentumRequestNativeSpaceMove(CGWindowID windowID, uint64_t spaceID) {
    NSCAssert([NSThread isMainThread], @"Native Space moves must run on the main thread");
    PerformOperation perform = NativeMoveOperation();
    Class cls = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
    SEL selector = NSSelectorFromString(@"initWithWindows:spaceID:");
    if (!windowID || !spaceID || !perform || !cls || ![cls instancesRespondToSelector:selector]) return NO;
    id operation = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)([cls alloc], selector, @[@(windowID)], spaceID);
    if (!operation) return NO;
    // The return value is undocumented, not a success code. Swift confirms actual membership.
    perform((__bridge void *)operation);
    return YES;
}
