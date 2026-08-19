# OS X SAT SMART Driver (RJVB Fork)

A macOS kernel extension (kext) that enables S.M.A.R.T. (Self-Monitoring, Analysis and Reporting Technology) support for external USB/FireWire hard drives connected via SAT (SCSI/ATA Translation).

## Building

### Requirements

- Xcode with Command Line Tools
- macOS SDK

### Build Commands

```bash
# Build the project (Release configuration)
cd SATSMARTDriver
xcodebuild -configuration Release -project SATSMARTDriver.xcodeproj ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO

# Create installer package and DMG
cd ..
make pkg CONFIGURATION=Release
make dmg CONFIGURATION=Release
```

**Note:** The `ARCHS=x86_64` flag is required because the i386 architecture is deprecated in modern Xcode SDKs.

### Build Outputs

- `SATSMARTDriver.kext` - The kernel extension
- `SATSMARTLib.plugin` - The SMART library plugin
- `smart_status` - Command-line tool to check SMART status
- `SATSMARTDriver-<version>.pkg` - Installer package
- `SATSMARTDriver-<version>.dmg` - Disk image containing the installer

## Modern macOS/Xcode Compatibility Fix

This fork includes fixes for building on modern macOS versions (High Sierra and later) with recent Xcode SDKs.

### The Problem

The original code uses Apple's `AssertMacros.h` convenience macros (`require`, `require_action`, `require_quiet`, `require_noerr_action`) with goto-label error handling patterns:

```c
require(condition, ErrorExit);
// ...
ErrorExit:
    return error;
```

Starting with macOS High Sierra (10.13) and iOS 11, these legacy macros are disabled by default. The new versions use double-underscore prefixes (`__Require`, `__Require_Action`, etc.).

### The Fix

The following files were modified to re-enable the legacy macros by defining `__ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES` before including `AssertMacros.h`:

- `SATSMARTDriver/IOSATDriver.cpp`
- `SATSMARTDriver/TestTools/smart_status.c`
- `SATSMARTDriver/TestTools/ATASMARTSample.c`

```c
// Enable legacy require/require_action/require_quiet macros from AssertMacros.h
#define __ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES 1

#include <AssertMacros.h>
```

## Installation

1. Mount the DMG file
2. Run the installer package
3. Restart your Mac (or manually load the kext)

The driver installs to `/Library/Extensions/`.

## Usage

After installation, external drives connected via USB/FireWire enclosures that support SAT should report SMART data to disk utility applications like DriveDx or smartmontools.

Use the included `smart_status` tool to check SMART status from the command line.

## License

See individual source files for license information. The project contains code under various licenses including Apple sample code license and BSD-style licenses.

## Credits

- Original author: Jarkko Sonninen
- RJVB fork maintainer: RJVB
- Modern SDK compatibility fixes: Warp
