def _fmt_str_array(array):
    return "[" + ",".join(['"{}"'.format(a) for a in array]) + "]"

def _fmt_pairs(array):
    return "[" + ",".join([_fmt_str_array(x) for x in array]) + "]"

def _search_path(repository_ctx, name, paths):
    for d in paths:
        p = repository_ctx.path(d + "/" + name)
        if p.exists:
            return p
    fail("{} not found\nSearch path: {}".format(name, paths))

def _load_system_exe_impl(repository_ctx):
    name = repository_ctx.attr.name
    system_paths = [x.strip() for x in repository_ctx.os.environ["PATH"].split(":")]
    search_paths = repository_ctx.attr.paths + system_paths

    pairs = []
    for name, real_name in repository_ctx.attr.execs.items():
        src = _search_path(repository_ctx, real_name, search_paths)
        repository_ctx.symlink(src, "_" + name)
        pairs.append([name, "_" + name])

    build = repository_ctx.template("BUILD", Label("//system:BUILD.tmpl"), substitutions = {
        "%{pairs}": _fmt_pairs(pairs),
    }, executable = False)

load_system_exe = repository_rule(
    implementation = _load_system_exe_impl,
    environ = ["PATH"],
    attrs = {
        "execs": attr.string_dict(
            doc = "Direct system path of file",
        ),
        "paths": attr.string_list(
            doc = "Extra paths to search before PATH",
        ),
    },
    configure = True,
)
