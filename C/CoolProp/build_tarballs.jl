# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

name = "CoolProp"
version = v"6.4.1"

# Collection of sources required to complete build
sources = [
    ArchiveSource("https://sourceforge.net/projects/coolprop/files/CoolProp/$version/source/CoolProp_sources.zip", "b10b2be2f88675b7e46cae653880be93558009c8970d23e50ea917ce095791f6"),
]

# Adjusted version for Mac M1 support
version = v"6.4.2"

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir

sed -i 's/Windows/windows/' CoolProp.sources/dev/Tickets/60.cpp
sed -i 's/Windows/windows/' CoolProp.sources/src/CPfilepaths.cpp
sed -i 's/.*-m.*BITNESS.*//' CoolProp.sources/CMakeLists.txt

mkdir build
cd build
cmake -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_FIND_ROOT_PATH=$prefix -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} -DCMAKE_BUILD_TYPE=Release -DCOOLPROP_SHARED_LIBRARY=ON ../CoolProp*/
VERBOSE=ON cmake --build . --config Release --target CoolProp -- -j${nproc}
mkdir -p ${libdir}
cp -a *CoolProp* ${libdir}
install_license $WORKSPACE/srcdir/CoolProp*/LICENSE
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = supported_platforms()
filter!(p -> arch(p) != "powerpc64le", platforms)
platforms = expand_cxxstring_abis(platforms)

# The products that we will ensure are always built
products = [
    LibraryProduct("libCoolProp", :libcoolprop)
]

# Dependencies that must be installed before this package can be built
dependencies = Dependency[
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.6")
