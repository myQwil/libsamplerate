# libsamplerate

This is [libsamplerate](https://libsndfile.github.io/libsamplerate/),
packaged for [Zig](https://ziglang.org/).

## How to use it

First, update your `build.zig.zon`:

```
zig fetch --save https://github.com/myQwil/libsamplerate/archive/refs/heads/main.tar.gz
```

Next, add this snippet to your `build.zig` script:

```zig
const libsamplerate_dep = b.dependency("libsamplerate", .{
    .target = target,
    .optimize = optimize,
});
```

From here, you can add it to your project, either as a library or a module.

### As a library
```zig
your_compilation.linkLibrary(libsamplerate_dep.artifact("samplerate"));
```

### As a module
```zig
your_compilation.root_module.addImport("samplerate", libsamplerate_dep.module("samplerate")),
```
