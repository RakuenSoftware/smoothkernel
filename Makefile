# Top-level orchestration. Reads build.env (or build-env supplied via env).
# Each target is a thin wrapper around the recipe in recipes/.
#
# Usage:
#   cp examples/smoothnas.env build.env
#   $EDITOR build.env
#   make kernel
#   make zfs
#   make clean

ENV_FILE ?= build.env
ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif

OUT_DIR ?= $(CURDIR)/out

.PHONY: help kernel zfs clean show

help:
	@echo "smoothkernel — Smooth* shared kernel build harness"
	@echo ""
	@echo "Targets:"
	@echo "  kernel    Build linux-{image,headers,libc-dev} .debs"
	@echo "  zfs       Build OpenZFS .debs (zfs-dkms + libs + utils)"
	@echo "  clean     Remove build trees + out/"
	@echo "  show      Print the resolved build environment"
	@echo ""
	@echo "Required env (set in $(ENV_FILE) or shell):"
	@echo "  KERNEL_VERSION    e.g. 6.18.22"
	@echo "  LOCALVERSION      e.g. -smoothnas-lts (must start with -)"
	@echo "  ZFS_VERSION       e.g. 2.4.1"
	@echo "  CONFIG_SOURCE     path to seed .config (per-OS)"
	@echo ""
	@echo "Optional env:"
	@echo "  OUT_DIR           default $(OUT_DIR)"
	@echo "  BUILD_THREADS     default \$$(nproc)"

show:
	@echo "ENV_FILE        = $(ENV_FILE)"
	@echo "KERNEL_VERSION  = $(KERNEL_VERSION)"
	@echo "LOCALVERSION    = $(LOCALVERSION)"
	@echo "ZFS_VERSION     = $(ZFS_VERSION)"
	@echo "CONFIG_SOURCE   = $(CONFIG_SOURCE)"
	@echo "OUT_DIR         = $(OUT_DIR)"
	@echo "BUILD_THREADS   = $(BUILD_THREADS)"

kernel:
	@$(CURDIR)/recipes/build-kernel.sh

zfs:
	@$(CURDIR)/recipes/build-zfs.sh

clean:
	rm -rf build/ $(OUT_DIR)
