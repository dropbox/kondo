# Kondo


[![Build Status](https://travis-ci.org/dropbox/Kondo.svg?branch=main)](https://travis-ci.org/dropbox/Kondo)
[![codecov](https://codecov.io/gh/dropbox/Kondo/branch/main/graph/badge.svg)](https://codecov.io/gh/dropbox/Kondo)

A tool to help extract code into modules, move modules, rename modules, and analyze the structure of the codebase.

# Usage

## Create XCode Project

```
swift package generate-xcodeproj
```

## Build project for commandline

```
swift build
cp .build/debug/refactor /usr/local/bin/
```

## Use generated tool

```
refactor create buckPath=/Users/jlaws/src/xplat1/tools/buck/bin/buck shellPath=/Users/jlaws/src/xplat1 jsonFile=/Users/jlaws/Desktop/create.json

refactor move buckPath=/Users/jlaws/src/xplat1/tools/buck/bin/buck shellPath=/Users/jlaws/src/xplat1 jsonFile=/Users/jlaws/Desktop/move.json

refactor parse buckPath=/Users/jlaws/src/xplat1/tools/buck/bin/buck shellPath=/Users/jlaws/src/xplat1 jsonFile=/Users/jlaws/Desktop/parse.json
```

### Create Input Json Example

```
{
    "modules": [
        {
            "destination": "ios/dbapp/extensions/account",
            "files": [
                "dbapp-ios/Dropbox/DropboxExtensions/DBExtensionAccountAndSessionProtocol.h",
                "dbapp-ios/Dropbox/DropboxExtensions/DBExtensionUser.h",
                "dbapp-ios/Dropbox/DropboxExtensions/DBExtensionUser.m",
            ],
        },
        {
            "destination": "ios/common/chooser/filter",
            "files": [
                "dbapp-ios/Dropbox/DropboxExtensions/DBChooserFileFilter.h",
                "dbapp-ios/Dropbox/DropboxExtensions/DBChooserFileFilterUTI.h",
                "dbapp-ios/Dropbox/DropboxExtensions/DBChooserFileFilterUTI.m",
            ],
        },
    ],
    "projectBuildTargets": [
        "//dbapp-ios/Dropbox:DropboxPackage",
    ],
    "ignoreFolders": [
        "android",
        "android-util",
        "arc_lib",
        "bmbf-gen-tmp",
        "buck-out",
        "ci",
        "configs",
        "dbx/external"
        "interviews",
        "intl",
        "mac",
        "paper",
        "shared",
        "tools",
    ]
}
```

### Move Input Json Example

```
{
    "paths": [
        {
            "source": "dbx/core/account_unlinker",
            "destination": "ios/common/account_unlinker",
        },
        {
            "source": "dbx/core/appearance",
            "destination": "ios/common/appearance",
        },
    ],
    "ignoreFolders": [
        "android",
        "android-util",
        "arc_lib",
        "bmbf-gen-tmp",
        "buck-out",
        "ci",
        "configs",
        "interviews",
        "intl",
        "tools"
    ]
}
```

### Parse Input Json Example

```
{
    "csvOutputPath": "/Users/jlaws/Desktop/types.csv",
    "jsonOutputPath": "/Users/jlaws/Desktop/types.json",
    "overrides": [

    ],
    "filePaths": [
        "dbapp-ios/Dropbox/Classes/Helpers/WidgetActionsHandler/DBWidgetActionsHandler.m",
        "dbapp-ios/Dropbox/Classes/Helpers/WidgetActionsHandler/DBWidgetActionsHandler.h",
        "dbapp-ios/Dropbox/Classes/Helpers/ThumbnailHelpers/DBFileEntryThumbnailManager.h",
    ]
}
```


## View graph output

```
brew install graphviz
```

# Contribute

## Setup SwiftFormat

```
brew install SwiftFormat
```

## Setup SwiftLint

```
brew install swiftlint
```
