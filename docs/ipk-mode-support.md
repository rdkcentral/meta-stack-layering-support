# ipk mode support [Experimental feature]
With the help of IPK mode support, we can switch the components between source and IPK mode.

IPK mode means, build will skip the corresponding package recipe from excuting its default tasks and use the IPK of that package to resolve both build time and runtime dependencies.

### Advantages:
- Consistency Across Releaseing IPKs:
Although there is an Artifactory feed for each release, the same version of IPKs have different checksums across feeds, with no clear way to identify the cause of these differences. By standardizing IPK consumption, we can maintain consistency across releases, ensuring that components are only rebuilt and IPKs are regenerated when there are changes in the source code or a significant number of dependent packages have changed.
- Artifactory Storage Efficiency:
IPKs are stored in Artifactory, which uses checksums for storage. This feature ensures that file checksums change only if there is a version change in the package, resulting in significant long-term storage savings when JFrog employs checksum-based storage.
- Easy to identify the reasons for rebuilds of each package:
In the IPK consumption model, identifying the reason for a rebuild is easier, as it is based on version changes and can be fully controlled by engineers.
- Reduces Build Space:
Enabling IPK consumption for each package can significantly reduce the build space, as pre-built packages are used instead of rebuilding everything. 
- Reduces Build Time:
The IPK consumption model can lead to a substantial reduction in build time, as packages do not need to be rebuilt if no changes are detected. 
- Eliminates unnecessary rebuilds of package sources:
IPK consumption model only triggers rebuilds when there is a significant change in dependencies or source code. 
- Track each changes through versioning: Triggering the build from source by engineers using the proper version, instead of relying on sstate, helps to track the specific changes included in each IPK package.
- Provides a controlled and stable development environment:
Adopting fully tested released version IPKs provides a controlled and stable development environment, reducing the risks and unpredictability that can come with using cached builds.

### Feature 
- Build from source only if there is a version change in the package or if specified in the command line using bitbake <package>.
- The lower-level dependencies will be handled automatically. If there is a version change in the dependency tree, it will rebuild those packages from the source as well.
For example, if pkg1 depends on pkg2, and pkg2 has a version change compared to the previous release, then while building pkg1, it will rebuild pkg2 from the source as well (since the updated pkg2 IPK will not be available in the feeds).
- If a target package has a dependency on a version-changed package, it will throw a build failure during recipe parsing and provide information regarding the necessary changes. Currently, this is configured to detect major version changes, but it can be adjusted to check for either version changes or both version and revision changes.
Use cases, bitbake <packagegroup> or bitbake <target image>
It will check all the target package dependencies with pkg1. If pkg1 has a major version change, it will stop the build and provide information about the packages that have a dependency on pkg1.

## To trigger build from source:
- Either package name should mention in the command line eg: bitbake openssl
- Or if there is a version mismatch from the previous release feed. 

## To enble IPK consumption:
- Define STACK_LAYER_EXTENSION variable with the IPK feed arch name. eg: STACK_LAYER_EXTENSION = "armv7at2hf-neon".
- IPK_FEED_URIS += " ${STACK_LAYER_EXTENSION}##<Artifactory/ipk feed path> ".
- Inherit "kernel-devel" in linux recipes. This will generate the kernel devel IPK package with the required build artifacts. These build artifacts help to compile kernel modules without using the Linux source.
- Update and verify that all package IPKs are created with the proper dependencies.
- Implement a review process to ensure proper version updates.

  This will consume all the packages available from the feed URI defined for "armv7at2hf-neon" as IPKs, unless the conditions mentioned in "To trigger build from source" are met.


