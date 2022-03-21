load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")
load("@bazel_clang_tidy//clang_tidy:clang_tidy.bzl", "clang_tidy_rule")

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

clang_tidy_rule(
    name = "file_count",
    extension = "h",
    deps = ["example"],
)
