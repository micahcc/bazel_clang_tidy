load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")
load("@com_github_micahcc_bazel_clang_tidy//clang_tidy:clang_tidy.bzl", "clang_tidy")

cc_library(
    name = "lib",
    srcs = ["lib.cpp"],
    hdrs = ["lib.hpp"],
)

cc_binary(
    name = "example",
    srcs = ["app.cpp"],
    deps = [":lib"],
)

clang_tidy()
