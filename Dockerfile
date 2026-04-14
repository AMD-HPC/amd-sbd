# SBD Artifact Container (A3)
# Reproduces results from "Scaling Sample-Based Quantum Diagonalization
# on GPU-Accelerated Systems using OpenMP Offload"
#
# Based on AMD InfinityHub reference for GPU-aware MPI:
#   https://github.com/amd/InfinityHub-CI/tree/main/base-gpu-mpi-rocm-docker
#
# Build:
#   docker build -t sbd-artifact .
#   docker build --build-arg OFFLOAD_ARCH=gfx90a -t sbd-frontier .
#
# Run (8 MI300X GPUs):
#   docker run --rm --device=/dev/kfd --device=/dev/dri \
#     --security-opt seccomp=unconfined sbd-artifact

FROM rocm/dev-ubuntu-22.04:6.4-complete

ARG OFFLOAD_ARCH=gfx942
ARG SBD_BRANCH=sc26-artifacts
ARG UCX_BRANCH=v1.19.0
ARG UCC_BRANCH=v1.5.1
ARG OMPI_BRANCH=v5.0.8

# Install build tools and OpenBLAS
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libnuma-dev \
    flex \
    hwloc \
    libxml2-dev \
    python3 \
    libopenblas-dev \
    gfortran \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

ENV ROCM_PATH=/opt/rocm
ENV UCX_PATH=/opt/ucx
ENV UCC_PATH=/opt/ucc
ENV OMPI_PATH=/opt/ompi

# Build UCX with ROCm support
WORKDIR /tmp
RUN git clone https://github.com/openucx/ucx.git -b ${UCX_BRANCH} \
  && cd ucx \
  && ./autogen.sh \
  && mkdir build && cd build \
  && ../contrib/configure-release --prefix=$UCX_PATH \
     --with-rocm=$ROCM_PATH \
     --with-cma \
     --without-knem \
     --without-xpmem \
     --without-cuda \
     --enable-optimizations \
     --disable-logging \
     --disable-debug \
     --disable-examples \
  && make -j $(nproc) \
  && make install \
  && rm -rf /tmp/ucx

# Build UCC with UCX + ROCm support
RUN git clone https://github.com/openucx/ucc.git -b ${UCC_BRANCH} \
  && cd ucc \
  && ./autogen.sh \
  && mkdir build && cd build \
  && ../configure --prefix=$UCC_PATH \
     --with-rocm=$ROCM_PATH \
     --with-ucx=$UCX_PATH \
     --with-rccl=no \
  && make -j $(nproc) \
  && make install \
  && rm -rf /tmp/ucc

# Build OpenMPI with UCX + UCC + ROCm support
RUN git clone --recursive https://github.com/open-mpi/ompi.git -b ${OMPI_BRANCH} \
  && cd ompi \
  && ./autogen.pl \
  && mkdir build && cd build \
  && ../configure --prefix=$OMPI_PATH \
     --with-ucx=$UCX_PATH \
     --with-ucc=$UCC_PATH \
     --with-rocm=$ROCM_PATH \
     --with-cma \
     --enable-mpi1-compatibility \
     --enable-pmix-binaries \
     --with-pmix=internal \
     --enable-mpi \
     --enable-mpi-fortran=no \
     --disable-man-pages \
     --disable-debug \
  && make -j $(nproc) \
  && make install \
  && rm -rf /tmp/ompi

ENV PATH=$OMPI_PATH/bin:$UCX_PATH/bin:$UCC_PATH/bin:$PATH
ENV LD_LIBRARY_PATH=$OMPI_PATH/lib:$UCX_PATH/lib:$UCC_PATH/lib:$ROCM_PATH/lib:$LD_LIBRARY_PATH
ENV OMPI_CXX=$ROCM_PATH/llvm/bin/clang++
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV OMP_NUM_THREADS=16
ENV UCX_WARN_UNUSED_ENV_VARS=n
ENV UCX_LOG_LEVEL=error

# Clone SBD source code (A1) at pinned commit
RUN git clone -b ${SBD_BRANCH} --depth 1 \
    https://github.com/AMD-HPC/amd-sbd.git /opt/amd-sbd

# Clone test data (A2)
RUN git clone --depth 1 https://github.com/r-ccs-cms/sbd.git /opt/sbd-data

WORKDIR /opt/amd-sbd/applications/selected_basis_diagonalization/src

# Patch Makefile for container environment:
#  - Use OMPI_CXX (set via env) instead of MPICH_CXX
#  - Link against system OpenBLAS shared library
#  - Set offload architecture from build arg
RUN sed -i \
    -e 's|export MPICH_CXX=.*|# (set via OMPI_CXX environment variable)|' \
    -e 's|LDFLAGS = -fopenmp .*/libopenblas.a|LDFLAGS = -fopenmp -lopenblas|' \
    -e "s|--offload-arch=gfx90a|--offload-arch=${OFFLOAD_ARCH}|" \
    Makefile

RUN make GPU=1

# Verify the binary was produced
RUN test -x ./diag

# Default: run the N2 benchmark on 8 GPUs
CMD ["mpirun", "-np", "8", \
     "--mca", "pml", "ucx", \
     "--mca", "btl", "^vader,tcp,openib,uct", \
     "--map-by", "socket:PE=16", \
     "./diag", \
     "--fcidump", "/opt/sbd-data/data/n2/fcidump.txt", \
     "--adetfile", "/opt/sbd-data/data/n2/1em7-alpha.txt", \
     "--adet_comm_size", "4", "--bdet_comm_size", "2", \
     "--task_comm_size", "1", "--tolerance", "1.0e-4", \
     "--iteration", "2", "--max_time", "1200", \
     "--method", "0", "--block", "10", \
     "--shuffle", "1", "--rdm", "0", "--bit_length", "36"]
