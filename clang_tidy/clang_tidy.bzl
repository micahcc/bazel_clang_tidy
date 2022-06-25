load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

CompileJobInfo = provider(
    fields = {
        "name": "Name of rule",
        "srcs": "Input Files",
        "deps": "Dependencies (changes trigger rebuild)",
        "flags": "",
        "defines": "",
        "local_defines": "",
        "framework_includes": "",
        "includes": "",
        "quote_includes": "",
        "system_includes": "",
    },
)

def _cleanse(string):
    return string.replace(".", "_").replace(":", "")

def _rule_sources(ctx):
    srcs = []
    if hasattr(ctx.rule.attr, "srcs"):
        for src in ctx.rule.attr.srcs:
            srcs += [src for src in src.files.to_list() if src.is_source]
    if hasattr(ctx.rule.attr, "hdrs"):
        for src in ctx.rule.attr.hdrs:
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
    if not CcInfo in target:
        return []

    discriminator = target.label.name
    toolchain_flags = _toolchain_flags(ctx)
    rule_flags = ctx.rule.attr.copts if hasattr(ctx.rule.attr, "copts") else []
    flags = _safe_flags(toolchain_flags + rule_flags)
    compilation_context = target[CcInfo].compilation_context
    srcs = _rule_sources(ctx)

    return [CompileJobInfo(
        name = discriminator,
        srcs = srcs,
        deps = compilation_context.headers,
        flags = flags,
        defines = compilation_context.defines.to_list(),
        local_defines = compilation_context.defines.to_list(),
        framework_includes = compilation_context.framework_includes.to_list(),
        includes = compilation_context.includes.to_list(),
        quote_includes = compilation_context.quote_includes.to_list(),
        system_includes = compilation_context.system_includes.to_list(),
    )]

compile_job_aspect = aspect(
    implementation = _compile_job_aspect_impl,
    fragments = ["cpp"],
    attrs = {
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)

def _clang_tidy_genpatch_impl(ctx):
    clang_tidy_exe = ctx.attr.clang_tidy.files.to_list()[0]
    clang_apply_exe = ctx.attr.clang_apply.files.to_list()[0]
    diff_exe = ctx.attr.diff.files.to_list()[0]

    deps = ctx.attr.dep[CompileJobInfo].deps
    srcs = ctx.attr.dep[CompileJobInfo].srcs

    name = ctx.attr.dep[CompileJobInfo].name
    flags = ctx.attr.dep[CompileJobInfo].flags
    defines = ctx.attr.dep[CompileJobInfo].defines
    local_defines = ctx.attr.dep[CompileJobInfo].local_defines
    framework_includes = ctx.attr.dep[CompileJobInfo].framework_includes
    includes = ctx.attr.dep[CompileJobInfo].includes
    quote_includes = ctx.attr.dep[CompileJobInfo].quote_includes
    system_includes = ctx.attr.dep[CompileJobInfo].system_includes

    last_config = ctx.attr.configs[-1]
    config = last_config.files.to_list()

    # TODO(micah)
    # would probably want to make this a passed in option to the script we are generating

    # add args specified by the toolchain, on the command line and rule copts
    all_flags = []
    for flag in flags:
        all_flags.append(flag)

    # add defines
    for define in defines:
        all_flags.append("-D" + define)

    for define in local_defines:
        all_flags.append("-D" + define)

    # add includes
    for i in framework_includes:
        all_flags.append("-F" + i)

    for i in includes:
        all_flags.append("-I" + i)

    for i in quote_includes:
        all_flags.append("-iquote")
        all_flags.append(i)

    for i in system_includes:
        all_flags.append("-isystem")
        all_flags.append(i)

    patches = []

    # add source to check
    for infile in srcs:
        inputs = depset(direct = config + [infile], transitive = [deps])

        # for each input file, make a script and run it
        script = ctx.actions.declare_file(_cleanse(infile.short_path) + "_clang_tidy.sh")
        patch = ctx.actions.declare_file(_cleanse(infile.short_path) + "_clang_tidy.patch")
        ctx.actions.expand_template(
            template = ctx.file._run_clang_tidy_template,
            output = script,
            substitutions = {
                "%CLANG_TIDY%": clang_tidy_exe.path,
                "%CLANG_APPLY%": clang_apply_exe.path,
                "%DIFF%": diff_exe.path,
                "%CONFIG_FILE%": config[0].path,
                "%INPUTS%": infile.short_path,
                "%FLAGS%": " ".join(all_flags),
                "%PATCH%": patch.path,
            },
        )

        ctx.actions.run_shell(
            mnemonic = "ClangTidy",
            command = script.path,
            inputs = inputs,
            tools = [script, clang_tidy_exe, clang_apply_exe, diff_exe],
            outputs = [patch],
        )

        patches.append(patch)

    join_script = ctx.actions.declare_file(ctx.label.name + "_join.sh")
    ctx.actions.expand_template(
        template = ctx.file._join_patches_template,
        output = join_script,
        substitutions = {
            "%PATCHES%": " ".join([f.path for f in patches]),
            "%OUTPUT_PATCH%": ctx.outputs.patch.path,
        },
    )

    ctx.actions.run_shell(
        mnemonic = "JoinClangTidyPatches",
        command = join_script.path,
        inputs = patches,
        tools = [join_script],
        outputs = [ctx.outputs.patch],
    )

clang_tidy_genpatch = rule(
    implementation = _clang_tidy_genpatch_impl,
    attrs = {
        "dep": attr.label(aspects = [compile_job_aspect]),
        "clang_apply": attr.label(
            mandatory = True,
            doc = "clang-apply-replacements",
        ),
        "clang_tidy": attr.label(
            mandatory = True,
            doc = "clang-tidy",
        ),
        "diff": attr.label(
            mandatory = True,
            doc = "Diff executable",
        ),
        "configs": attr.label_list(allow_empty = True, allow_files = True),
        "_run_clang_tidy_template": attr.label(
            default = Label("@com_github_micahcc_bazel_clang_tidy//clang_tidy:run_clang_tidy.sh"),
            allow_single_file = True,
        ),
        "_join_patches_template": attr.label(
            default = Label("@com_github_micahcc_bazel_clang_tidy//clang_tidy:join_patches.sh"),
            allow_single_file = True,
        ),
        "patch": attr.output(mandatory = True),
    },
)

def _clang_tidy_test_impl(ctx):
    """
    If clang-tidy produced diagnostic outputs or a patch then return false
    """
    patch = ctx.file.patch
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = ctx.outputs.executable,
        substitutions = {
            "%LOCAL_PATCH_FILE%": patch.short_path,
            "%OUT_PATCH_FILE%": patch.path,
        },
    )

    # To ensure the files needed by the script are available, we put them in
    # the runfiles.
    runfiles = ctx.runfiles(files = [patch])

    return [DefaultInfo(runfiles = runfiles)]

clang_tidy_test = rule(
    implementation = _clang_tidy_test_impl,
    attrs = {
        "patch": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The patch file",
        ),
        "_template": attr.label(
            default = Label("@com_github_micahcc_bazel_clang_tidy//clang_tidy:check_clang_tidy.sh"),
            allow_single_file = True,
        ),
    },
    test = True,
)

def _is_c_file(s):
    return s.endswith(".c") or s.endswith(".cc") or s.endswith(".c++") or s.endswith(".cxx")

def clang_tidy(
        clang_tidy = "@sys//:clang-tidy",
        clang_apply = "@sys//:clang-apply-replacements",
        diff = "@sys//:diff"):
    """For every rule in the BUILD file so far, adds a test rule that runs
    clang_tidy on it.
    """
    tags = ["lint", "clang_tidy"]

    configs = native.glob([".clang-tidy"])

    # Iterate over all rules.
    for rule in native.existing_rules().values():
        gen = rule["generator_function"]
        name = rule["name"]
        if gen == "cc_library" or gen == "cc_binary":
            prefix = "_" + name + "_clang_tidy"
            clang_tidy_genpatch(
                name = prefix,
                configs = configs,
                clang_tidy = clang_tidy,
                clang_apply = clang_apply,
                diff = diff,
                dep = ":" + name,
                patch = prefix + ".patch",
                tags = tags,
            )

            clang_tidy_test(
                name = prefix + "_result",
                patch = ":" + prefix + ".patch",
                tags = tags,
            )
