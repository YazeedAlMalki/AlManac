# Source this before using swift on yamal.
export SWIFT_HOME="$HOME/.local/swift/swift-6.3.3-RELEASE-ubuntu24.04"
export PATH="$SWIFT_HOME/usr/bin:$PATH"
# Ubuntu 26.04 ships libxml2.so.16; the ubuntu24.04 toolchain wants .so.2.
export LD_LIBRARY_PATH="$HOME/.local/swiftdeps:${LD_LIBRARY_PATH:-}"
