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

## To trigger build from source:
- Either package name should mention in the command line eg: bitbake openssl
- Or if there is a version mismatch from the previous release feed. 

## To enble IPK consumption:
- Define STACK_LAYER_EXTENSION variable with the IPK feed arch name. eg: STACK_LAYER_EXTENSION = "armv7at2hf-neon-oe-linux-gnueabi".
- IPK_FEED_URIS += " ${STACK_LAYER_EXTENSION}##<Artifactory/ipk feed path> ".
  
  This will consume all the packages available from the feed URI defined for "armv7at2hf-neon-oe-linux-gnueabi" as IPKs, unless the conditions mentioned in "To trigger build from source" are met.


