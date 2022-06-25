# vi: ft=bzl
package(default_visibility = ["//visibility:public"])

sh_binary(
    name = name,
    srcs = [%{srcs}],
    deps = [%{deps}],
)
