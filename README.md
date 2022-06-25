# bazel_clang_tidy

Hook to run clang-tidy as part of tests.

Usage:

```py
# //:WORKSPACE
load(
    "@bazel_tools//tools/build_defs/repo:git.bzl",
    "git_repository",
)

git_repository(
       name = "com_github_micahcc_bazel_clang_tidy",
       commit = "69aa13e6d7cf102df70921c66be15d4592251e56",
       remote = "https://github.com/micahcc/bazel_clang_tidy.git",
)

load("@com_github_micahcc_bazel_clang_tidy//system:load_system.bzl", "load_system_exe")

# declare that we need certain system tools
load_system_exe(
    name = "sys",
    execs = {
        "diff": "diff",
        "clang-tidy": "clang-tidy-12",
        "clang-apply-replacements": "clang-apply-replacements-12",
    },
)
```

You can now run clang tidy check with build

```
bazel build //...
```

The results are checked with test:

```
bazel build //...
```

Note that the actual diffs are generated with build, which could extend build
times (but does enable caching!). If you don't want clang-tidy with all builds you
can add a filter:

```
build --build_tag_filters=-lint
```

## Features

- Run clang-tidy on any C++ target
- Use Bazel to cache clang-tidy reports: recompute stale reports only

## Example

## Requirements

- Bazel 4.0 or newer (might work with older versions)
