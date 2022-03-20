load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")
load("//:file_count.bzl", "file_count_rule")

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

file_count_rule(
    name = "file_count",
    extension = "h",
    deps = ["example"],
)
