# SBD Docker Container (Artifacts A3/A4)

Docker container for reproducing results from *"Scaling Sample-Based Quantum
Diagonalization on GPU-Accelerated Systems using OpenMP Offload"*.

## Prerequisites

- Docker (or Podman)
- AMD GPU with ROCm kernel driver installed on the host
- User must be in the `render` and `video` groups (or run with appropriate permissions)

Verify ROCm is working on the host:

```bash
rocminfo | grep gfx
```

## Building the Container

**For MI300X (default):**

```bash
docker build -t sbd-artifact .
```

**For other AMD GPU architectures:**

```bash
# MI250X (Frontier)
docker build --build-arg OFFLOAD_ARCH=gfx90a -t sbd-artifact .

# MI210
docker build --build-arg OFFLOAD_ARCH=gfx90a -t sbd-artifact .

# MI300A
docker build --build-arg OFFLOAD_ARCH=gfx942 -t sbd-artifact .
```

Use `rocminfo | grep gfx` on the host to determine the correct architecture.

Build takes approximately 10-15 minutes depending on network speed.

## Running the Benchmark

**Default run (8 GPUs, N2 test case with 1.81x10^8 determinants):**

```bash
docker run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --security-opt seccomp=unconfined \
  sbd-artifact
```

The `--security-opt seccomp=unconfined` flag is optional but recommended for HPC
workloads -- it enables unrestricted memory mapping for proper NUMA-aware GPU access.

This executes `mpirun -np 8` with the parameters matching Table IV of the paper.
Expected runtime: ~2 minutes on 8 MI300X GPUs.

**Interactive shell (for debugging or exploring):**

```bash
docker run --rm -it \
  --device=/dev/kfd \
  --device=/dev/dri \
  --security-opt seccomp=unconfined \
  sbd-artifact /bin/bash
```

