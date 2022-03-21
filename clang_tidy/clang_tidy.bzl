load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

CompileJobInfo = provider(
    fields = {
        "inputs": "Input Files",
        "flags": "",
        "defines": "",
        "local_defines": "",
        "framework_includes": "",
        "includes": "",
        "quote_includes": "",
        "system_include": "",
    },
)

def _rule_sources(ctx):
    srcs = []
    if hasattr(ctx.rule.attr, "srcs"):
        for src in ctx.rule.attr.srcs:
            srcs += [src for src in src.files.to_list() if src.is_source]
    return srcs

def _toolchain_flags(ctx):
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = ctx.fragments.cpp.cxxopts + ctx.fragments.cpp.copts,
    )
    flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = "c++-compile",  # tools/build_defs/cc/action_names.bzl CPP_COMPILE_ACTION_NAME
        variables = compile_variables,
    )
    return flags

def _safe_flags(flags):
    # Some flags might be used by GCC, but not understood by Clang.
    # Remove them here, to allow users to run clang-tidy, without having
    # a clang toolchain configured (that would produce a good command line with --compiler clang)
    unsupported_flags = [
        "-fno-canonical-system-headers",
        "-fstack-usage",
    ]

    return [flag for flag in flags if flag not in unsupported_flags and not flag.startswith("--sysroot")]

def _compile_job_aspect_impl(target, ctx):
    # if not a C/C++ target, we are not interested
    print(target, ctx)
    if not CcInfo in target:
        return []

    discriminator = target.label.name
    toolchain_flags = _toolchain_flags(ctx)
    rule_flags = ctx.rule.attr.copts if hasattr(ctx.rule.attr, "copts") else []
    flags = _safe_flags(toolchain_flags + rule_flags)
    compilation_context = target[CcInfo].compilation_context
    srcs = _rule_sources(ctx)
    inputs = depset(direct = srcs, transitive = [compilation_context.headers])

    print(discriminator)
    print(toolchain_flags)
    print(rule_flags)
    return [CompileJobInfo(
        name = discriminator,
        inputs = inputs,
        flags = flags,
        defines = compilation_context.defines.to_list(),
        local_defines = compilation_context.defines.to_list(),
        framework_includes = compilation_context.framework_includes.to_list(),
        includes = compilation_context.includes.to_list(),
        quote_includes = compilation_context.quote_includes.to_list(),
        system_includes = compilation_context.system_includes.to_list(),
    )]

FileCountInfo = provider(
    fields = {
        "count": "number of files",
    },
)

def _file_count_aspect_impl(target, ctx):
    print(target)
    count = 0

    # Make sure the rule has a srcs attribute.
    if hasattr(ctx.rule.attr, "srcs"):
        # Iterate through the sources counting files
        for src in ctx.rule.attr.srcs:
            for f in src.files.to_list():
                if ctx.attr.extension == "*" or ctx.attr.extension == f.extension:
                    count = count + 1

    # Get the counts from our dependencies.
    for dep in ctx.rule.attr.deps:
        count = count + dep[FileCountInfo].count
    return [FileCountInfo(count = count)]

compile_job_aspect = aspect(
    implementation = _compile_job_aspect_impl,
    fragments = ["cpp"],
    attrs = {
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)

def _clang_tidy_rule_impl(ctx):
    print(ctx.attr)
    for dep in ctx.attr.deps:
        print(dep[FileCountInfo].count)

    print(ctx.attr.deps)
    clang_tidy_exe = ctx.attr.clang_tidy
    for dep in ctx.attr.deps:
        print(dep[CompileJobInfo])
        name = dep[CompileJobInfo].name
        inputs = dep[CompileJobInfo].inputs
        flags = dep[CompileJobInfo].flags
        defines = dep[CompileJobInfo].defines
        local_defines = dep[CompileJobInfo].local_defines
        framework_includes = dep[CompileJobInfo].framework_includes
        includes = dep[CompileJobInfo].includes
        quote_includes = dep[CompileJobInfo].quote_includes
        system_includes = dep[CompileJobInfo].system_includes

        # specify the output file - twice
        outfile = ctx.actions.declare_file("clang_tidy_" + name + ".clang-tidy.yaml")

        args = []
        args.append("--export-fixes")
        args.append(outfile.path)

        # add source to check
        for infile in inputs:
            args.append(infile.path)

        # start args passed to the compiler
        args.append("--")

        # add args specified by the toolchain, on the command line and rule copts
        for flag in flags:
            args.append(flag)

        # add defines
        for define in defines.to_list():
            args.append("-D" + define)

        for define in local_defines.to_list():
            args.append("-D" + define)

        # add includes
        for i in framework_includes.to_list():
            args.append("-F" + i)

        for i in includes.to_list():
            args.append("-I" + i)

        for i in quote_includes:
            args.append("-iquote")
            args.append(i)

        for i in system_includes:
            args.append("-isystem")
            args.append(i)

        args = " ".join(args)
        ctx.actions.run_shell(
            inputs = inputs,
            outputs = [outfile],
            arguments = [outfile.path, clang_tidy_exe.path, args],
            progress_message = "Run clang-tidy on {}".format(infile.short_path),
            tools = [clang_tidy_exe],
            # clang-tidy doesn't create a patchfile if there are no errors.
            # make sure the output exists, and empty if there are no errors,
            # so the build system will not be confused.
            command = "touch $1 && $2 \"$3\"",
            mnemonic = "ClangTidy",
        )

file_count_aspect = aspect(
    implementation = _file_count_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "extension": attr.string(values = ["*", "h", "cc"]),
    },
)

clang_tidy_rule = rule(
    implementation = _clang_tidy_rule_impl,
    attrs = {
        #"deps": attr.label_list(aspects = [file_count_aspect]),
        "deps": attr.label_list(aspects = [compile_job_aspect]),
        "clang_tidy": attr.label(),
        "extension": attr.string(),
    },
)
