## ycmapper-apple

This repository is a part of [Yellowcake](https://github.com/yellowcake-org) project.

### What it does

This viewer displays original Fallout™ maps, or compatible ones — given that all used resources exist at their corresponding paths. It uses [libycres](https://github.com/yellowcake-org/libycres) for reading maps and other resources and [libycvid](https://github.com/yellowcake-org/libycvid) which helps with graphics calculations (mostly specific to Fallout™’s geometry).

All application code is specific for  platforms, while all  dependencies are platform agnostic and may be used on any platform, where C99 exists. Thus, this repository is also proof-of-concept of my vision on platform agnostic software design.

Native code is responsible for all platform specific things: user interface (SwiftUI), GPU rendering (Metal), and so on.

### Why this is useful

Even from the start it allows you to view Fallout™ compatible maps, export selected regions to `.png` files, using modern Mac computer. I hope that one day it will become full-fledged map editor, or, even better, multipurpose tool for Fallout™ modders.

### How to get started

Root directory contains an XCode project with one target — macOS app. Dependencies are managed through git submodules, which are kept in `dependencies` directory. 

XCode project has reference to `cmake` folder, which is not stored under git. After you cloned repository, create `cmake` directory, and generate XCode project for every module you find in `dependencies` folder:

```
cmake -G Xcode ../dependencies/libycvid/
```

In foreseeable future all the above will be automated; the point here is not to store anything CMake can regenerate from submodules.

After XCode projects generated for all dependencies, you may run `ycmapper` target on your system from XCode.

### Where to get help

[GitHub Issues](https://github.com/yellowcake-org/ycmapper-apple/issues) is the right place. GitHub Discussion are disabled at the moment, but will be enabled in case of significant activity from community; Discord server might be run in addition, when number of people interested reaches reasonable milestone. As for now, I am handling all issues internally, using additional software.

### Who maintains and contributes

Currently, only [__@0xceed__](https://github.com/0xceed) is working on the library. While help from the community will be _very_ needed in the future, this early in development I need to focus on creating good example of my vision, guidelines and many, many more.