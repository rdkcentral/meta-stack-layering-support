# ipk mode within stack layer
With the help of IPK mode support, we can switch the components between source and IPK mode.

IPK mode means, build will skip the corresponding package recipe from executing its default tasks and use the IPK of that package to resolve both build time and runtime dependencies.

- Build from source only if there is a version change in the package or if specified in the command line using bitbake [package].
- The lower-level dependencies will be handled automatically. <br />If there is a version change in the dependency tree, it will rebuild those packages from the source as well.<br /><br />
Example, if pkg1 depends on pkg2, and pkg2 has a version change compared to the previous release, then while building pkg1, it will rebuild pkg2 from the source as well (since the updated pkg2 IPK will not be available in the feeds).
- If a target package has a dependency on a version-changed package, it will throw a build failure during recipe parsing and provide information regarding the necessary changes. Currently, this is configured to detect major version changes, but it can be adjusted to check for either version changes or both version and revision changes.<br /><br />
Use case, bitbake [packagegroup] or bitbake [target image]<br />
It will check all the target package dependencies with pkg1. If pkg1 has a major version change, it will stop the build and provide information about the packages which required version update due to dependency on pkg1.

### Advantages:
- Consistency across releasing IPKs:<br />
Although there is an Artifactory feed for each release, the same version of IPKs have different checksums across feeds, with no clear way to identify the cause of these differences. By standardizing IPK consumption, we can maintain consistency across releases, ensuring that components are only rebuilt and IPKs are regenerated when there are changes in the source code or a version of dependent packages have changed.
- Artifactory storage efficiency:<br />
IPKs are stored in Artifactory, which uses checksums for storage. This feature ensures that file checksums change only if there is a version change in the package, resulting in significant long-term storage savings when JFrog employs checksum-based storage.
- Easy to identify the reasons for rebuilds of each package:<br />
In the IPK consumption model, identifying the reason for a rebuild is easier, as it is based on version changes and can be fully controlled by engineers.
- Reduce build space:<br />
Enabling IPK consumption for each package can significantly reduce the build space, as pre-built packages are used instead of rebuilding everything. 
- Reduce build time:<br />
The IPK consumption model can lead to a substantial reduction in build time, as packages do not need to be rebuilt if no changes are detected. 
- Eliminates unnecessary rebuilds of package sources:<br />
IPK consumption model only triggers rebuilds when there is a significant change in dependencies or source code. 
- Track each changes through versioning: <br />
Triggering the build from source by engineers using the proper version, instead of relying on sstate, helps to track the specific changes included in each IPK package.
- Provides a controlled and stable development environment:<br />
Adopting fully tested released version IPKs provides a controlled and stable development environment, reducing the risks and unpredictability that can come with using cached builds.

## To trigger build from source:
- Either package name should mention in the command line<br /> e.g. bitbake openssl
- Or if there is a version mismatch from the previous release feed. 

## To enable IPK consumption:
- Define STACK_LAYER_EXTENSION variable with the IPK feed arch name.<br /> e.g.<br /> STACK_LAYER_EXTENSION = "armv7at2hf-neon"<br /> IPK_FEED_URIS += " ${STACK_LAYER_EXTENSION}##<Artifactory/ipk feed path> "<br /><br />  This will consume all the packages available from the feed URI defined for "armv7at2hf-neon" as IPKs, unless the conditions mentioned in "To trigger build from source" are met. We can set multiple arch feeds in STACK_LAYER_EXTENSION.
- Ensure proper version updates while reviewing each change in the components.

## Additional info
- EXCLUDE_IPK_FEEDS : This will skip the corresponding arch feed from the IPK consumption. <br /> EXCLUDE_IPK_FEEDS = "armv7at2hf-neon all", this will skip all the packages from "armv7at2hf-neon" and "all" archs from IPK consumption and process the recipes.<br /> 
- DEPENDS_VERSION_CHECK :  If set to "1", it will build the package from source, if a dependency's major version has changed. This will work only with packages set with global PV and PR . Example PV:pn-[openssl] = "1.1.1" <br />
- DEPENDS_ON_TARGET : If set to "1", it will build pkg from source, if it depends on target package <br />
