# Top-level orchestration. Reads build.env (or build-env supplied via env).
# Each target is a thin wrapper around the recipe in recipes/.
#
# Usage:
#   cp examples/smooth.env build.env
#   $EDITOR build.env
#   make kernel DEB_ARCH=amd64
#   make kernel DEB_ARCH=arm64
#   make zfs DEB_ARCH=amd64
#   make clean

ENV_FILE ?= build.env
ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif

DEB_ARCH ?= amd64
ARCHES ?= amd64 arm64
CONFIG_SOURCE ?= $(CURDIR)/configs/smooth-$(DEB_ARCH).config
CACHYOS_PATCHSET ?= cachyos-$(KERNEL_VERSION)
NOBARA_PATCHSET ?= nobara-picks
POST_NOBARA_PATCHSET ?= post-nobara-$(KERNEL_VERSION)
OUT_DIR ?= $(CURDIR)/out

.PHONY: help kernel kernel-all kernel-config-update kernel-config-update-all zfs clean show

help:
	@echo "smoothkernel — Smooth* shared kernel build harness"
	@echo ""
	@echo "Targets:"
	@echo "  kernel    Build linux-{image,headers,libc-dev} .debs"
	@echo "  kernel-all    Build kernel .debs for ARCHES='$(ARCHES)'"
	@echo "  kernel-config-update  Refresh configs/ against the patched kernel tree"
	@echo "  kernel-config-update-all  Refresh configs/ for ARCHES='$(ARCHES)'"
	@echo "  zfs       Build OpenZFS .debs (zfs-dkms + libs + utils)"
	@echo "  clean     Remove build trees + out/"
	@echo "  show      Print the resolved build environment"
	@echo ""
	@echo "Required env (set in $(ENV_FILE) or shell):"
	@echo "  KERNEL_VERSION    e.g. 6.18.22"
	@echo "  LOCALVERSION      e.g. -smoothkernel (must start with -)"
	@echo "  ZFS_VERSION       e.g. 2.4.1"
	@echo "  DEB_ARCH          amd64 or arm64 (default $(DEB_ARCH))"
	@echo "  CONFIG_SOURCE     path to canonical .config seed"
	@echo ""
	@echo "Optional env:"
	@echo "  CACHYOS_PATCHSET       default $(CACHYOS_PATCHSET)"
	@echo "  NOBARA_PATCHSET        default $(NOBARA_PATCHSET)"
	@echo "  POST_NOBARA_PATCHSET   default $(POST_NOBARA_PATCHSET)"
	@echo "  OUT_DIR           default $(OUT_DIR)"
	@echo "  BUILD_THREADS     default \$$(nproc)"
	@echo "  CROSS_COMPILE     optional kernel cross-compiler prefix"

show:
	@echo "ENV_FILE        = $(ENV_FILE)"
	@echo "KERNEL_VERSION  = $(KERNEL_VERSION)"
	@echo "LOCALVERSION    = $(LOCALVERSION)"
	@echo "ZFS_VERSION     = $(ZFS_VERSION)"
	@echo "DEB_ARCH        = $(DEB_ARCH)"
	@echo "ARCHES          = $(ARCHES)"
	@echo "CONFIG_SOURCE   = $(CONFIG_SOURCE)"
	@echo "CACHYOS_PATCHSET = $(CACHYOS_PATCHSET)"
	@echo "NOBARA_PATCHSET = $(NOBARA_PATCHSET)"
	@echo "POST_NOBARA_PATCHSET = $(POST_NOBARA_PATCHSET)"
	@echo "OUT_DIR         = $(OUT_DIR)"
	@echo "BUILD_THREADS   = $(BUILD_THREADS)"

kernel:
	@$(CURDIR)/recipes/build-kernel.sh

kernel-all:
	@set -e; for arch in $(ARCHES); do \
		echo "==> building kernel for $$arch"; \
		$(MAKE) DEB_ARCH=$$arch kernel; \
	done

kernel-config-update:
	@MODE=update-config $(CURDIR)/recipes/build-kernel.sh

kernel-config-update-all:
	@set -e; for arch in $(ARCHES); do \
		echo "==> refreshing kernel config for $$arch"; \
		$(MAKE) DEB_ARCH=$$arch kernel-config-update; \
	done

zfs:
	@$(CURDIR)/recipes/build-zfs.sh

clean:
	rm -rf build/ $(OUT_DIR)
