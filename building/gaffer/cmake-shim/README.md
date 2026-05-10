# Pre-rendered cmake shim overrides

Drop fully-formed cmake config files here when the auto-generated
shim from `setup-gaffer-deps.sh` is not enough. The setup script
copies the entire `lib/cmake/<pkg>/` subdirectory into the runtime
shim prefix, overriding anything the script generated for that
package.

## Currently empty (everything is auto-generated)

- `pxr` — generated from `libusd_*.so` discovered in the dep prefix.
- `OpenImageIO` — copied from the tarball with missing-tool entries
  stripped.

## When to add a pre-rendered shim here

- A package's tarball cmake config is fundamentally broken (not just
  missing tool entries) and needs a hand-edited replacement.
- We need to expose a target or variable the upstream config doesn't.
- An upstream cmake config and Moonray's `find_package` call disagree
  about a target name.

## Layout

Mirror the install-tree shape:

```
cmake-shim/
└── lib/
    └── cmake/
        └── <PackageName>/
            ├── <PackageName>Config.cmake
            └── <PackageName>Targets*.cmake
```
