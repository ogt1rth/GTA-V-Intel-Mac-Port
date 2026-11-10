# Intel build notes

The maintained instructions are in [BUILD_INTEL.md](BUILD_INTEL.md). They include prerequisites, the required x86_64 `PGMSL` shader translator, build commands and output paths.

The native Intel app/UI build has been checked using existing local generated engine objects and shaders. This is not a verification of a fresh-clone build: the compatible Dawn/Tint translator prerequisite is not automatically provisioned. A successful compile also does not establish sustained gameplay performance.

No game binaries, generated engine sources, game shader outputs or runtime logs belong in the public repository. See [PUBLISHING.md](PUBLISHING.md).
