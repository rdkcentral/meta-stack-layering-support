# IPK mode within a stack layer

IPK mode lets BitBake use a package from a configured feed instead of running that recipe's normal build tasks. Recipes still build from source when the requested package is targeted, a build-time dependency is targeted, a required package/version is unavailable, or a configured version check detects a dependency change.

## Configure feeds

Add the feed architecture to `STACK_LAYER_EXTENSION` and define its feed URI:

```bitbake
STACK_LAYER_EXTENSION:append = " armv7at2hf-neon"
IPK_FEED_URIS:append = " armv7at2hf-neon##https://example.invalid/path/to/ipk"
```

Feed entries use `<architecture>##<URI>`. The resolver reads `Packages.gz` to create local package/source/provider metadata. `EXCLUDE_IPK_FEEDS` excludes selected architectures from feed checks and metadata generation. The layer configuration also appends its derived GCC and glibc architectures to `STACK_LAYER_EXTENSION` and may add local or remote prebuilt feeds for them.

## Source-build conditions

- **Explicit target:** A recipe named on the BitBake command line is treated as a source-build target. A recipe with a build-time dependency that matches a requested target may also build from source.
- **Unavailable package:** If no matching package is found in the eligible feeds, the recipe builds from source.
- **Version mismatch:** When a matching recipe version is supplied to the resolver, it checks the package source/version metadata in the configured package architecture and applicable GCC/glibc feeds.
- **Dependency version change:** If `RECIPE_VER_LIST` contains versions for a recipe's build or runtime dependencies, the resolver compares those versions with feed metadata. A dependency version difference at the configured granularity can cause the dependent recipe to build from source.
- **Excluded package:** Packages listed in `IPK_EXCLUSION_LIST` are not consumed as IPKs.

`DISABLE_DEPS_SRC_BUILD = "1"` disables source rebuild decisions caused by targeted build-time dependencies and dependency version changes; it does not disable explicit-target handling or make an unavailable package available.

## Dependency version comparison

`RECIPE_VER_LIST` defaults to `${TOPDIR}/recipe_versions.txt`. The resolver expects rows with four pipe-separated fields: recipe, latest version, preferred version, and required version. It uses the required version when set, otherwise the preferred version, then the latest version. Missing files and malformed rows are reported in the BitBake log; without a usable version map, dependency-version checks cannot trigger rebuilds.

Set `DEPENDS_REBUILD_VERSION_MATCH` to control the comparison:

| Value | Comparison |
|---|---|
| `major` | Compare the first dot-separated version component. |
| `minor` | Compare the first two dot-separated components after removing a revision suffix. This is the default. |
| `patch` | Compare the version before a revision suffix. |
| Empty or another value | Compare the complete version string. |

Use the project's release process to generate/update the version file before the build. Running `bitbake -s` displays recipe versions; the command alone does not write `recipe_versions.txt`.

## Related controls

- `SKIP_RECIPE_IPK_PKGS = "1"` skips the stack-architecture restriction when checking whether a package is available as an IPK. It does not bypass the explicit exclusion list.
- `IPK_INCLUSION_LIST` names packages that should be added to common IPK staging. The default list includes `libgcc`, `gcc-runtime`, `gcc-sanitizers`, and `glibc`.
- `TARGET_BASED_IPK_STAGING = "1"` stages dependency IPKs for the requested target dependency graph when that graph is available. If it is unavailable, the staging task uses the dependency metadata it has.

## Build summary

The resolver records reasons such as an explicit target, a target dependency, a dependency version change, an unavailable IPK, or a missing prebuilt native archive in `REBUILD_REASON`. At build completion, it reports packages recorded as source builds by architecture.
