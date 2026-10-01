# libarchive project image
# Extends the shared anypoc base image with libarchive source and build

FROM zzjas/anypoc-base:latest

USER 0
RUN getent group 0 >/dev/null || echo 'root:x:0:' >> /etc/group
RUN getent passwd 0 >/dev/null || echo 'root:x:0:0:root:/root:/bin/bash' >> /etc/passwd
RUN apt-get update && apt-get install -y \
    cmake \
    ninja-build \
    clang \
    pkg-config \
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    libzstd-dev \
    liblz4-dev \
    libxml2-dev \
    libexpat1-dev \
    libacl1-dev \
    libattr1-dev \
    nettle-dev \
    libxxhash-dev \
    && rm -rf /var/lib/apt/lists/*

RUN getent group playground >/dev/null || groupadd playground && \
    id -u playground >/dev/null 2>&1 || useradd -m -s /bin/bash -g playground playground

RUN mkdir -p /opt/libarchive && chown -R playground:playground /home/playground /opt/libarchive

USER playground
WORKDIR /opt/libarchive

# Clone libarchive source code
RUN git clone --depth 1 https://github.com/libarchive/libarchive.git .

# Build libarchive CLI tools with sanitizers enabled.
RUN cmake -S . -B build -G Ninja \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_BUILD_TYPE=Debug \
        -DENABLE_TEST=OFF \
        -DENABLE_WERROR=OFF \
        -DCMAKE_C_FLAGS="-g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer" \
        -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" \
        -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined" && \
    cmake --build build -j "$(nproc)"

# Verify build
RUN test -x /opt/libarchive/build/bin/bsdtar && \
    test -x /opt/libarchive/build/bin/bsdcpio && \
    echo "Build verification: bsdtar and bsdcpio exist" || \
    (echo "Build verification failed: expected binaries not found" && exit 1)

WORKDIR /opt/libarchive
CMD ["/bin/bash"]
