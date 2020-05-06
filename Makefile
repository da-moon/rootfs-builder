include vars.mk
include contrib/makefiles/pkg/string/string.mk
include contrib/makefiles/pkg/color/color.mk
include contrib/makefiles/pkg/functions/functions.mk
include contrib/makefiles/target/buildenv/buildenv.mk
# include build/makefiles/target/go/go.mk
THIS_FILE := $(lastword $(MAKEFILE_LIST))
SELF_DIR := $(dir $(THIS_FILE))
DISTROS = $(notdir $(patsubst %/,%,$(dir $(wildcard ./distros/*/.))))
BUILD_TARGETS = $(DISTROS:%=build-%)
UNMOUNT_TARGETS = $(DISTROS:%=unmount-%)
CLEAN_TARGETS = $(DISTROS:%=clean-%)

.PHONY: build clean unmount print
.SILENT: build clean unmount  print

.PHONY: $(BUILD_TARGETS)
.SILENT: $(BUILD_TARGETS)
$(BUILD_TARGETS): 
	- $(call print_running_target)
	- $(eval name=$(@:build-%=%))
	- $(eval command=$(PWD)$(PSEP)distros$(PSEP)$(name)$(PSEP)build.sh)
	- chmod +x $(command)
	- cat "distros/$(name)/logo"
	- $(eval command=$(command) --root-dir $(BUILD_DIR)$(PSEP)$(name))
ifneq (${ARCH}, )
	- $(eval command=${command} --arch '$(ARCH)')
endif
ifneq (${CODENAME}, )
	- $(eval command=${command} --codename '$(CODENAME)')
endif
ifneq (${HOST_NAME}, )
	- $(eval command=${command} --host-name '$(HOST_NAME)')
endif
ifneq (${TIME_ZONE}, )
	- $(eval command=${command} --time-zone '$(TIME_ZONE)')
endif
ifneq (${WIFI_SSID}, )
	- $(eval command=${command} --wifi-ssid '$(WIFI_SSID)')
endif
ifneq (${WIFI_PASSWORD}, )
	- $(eval command=${command} --wifi-password '$(WIFI_PASSWORD)')
endif
    ifeq ($(DOCKER_ENV),true)
	- @$(MAKE) --no-print-directory \
	 -f $(THIS_FILE) shell \
	 docker_image="${BUILDER_IMAGE}" \
	 container_name="${BUILDER_CONTAINER_NAME}" \
	 mount_point="${BUILDER_CONTAINER_MOUNT_POINT} \
	 cmd="${command}"
    endif
    ifeq ($(DOCKER_ENV),false)
	- @$(MAKE) --no-print-directory \
	 -f $(THIS_FILE) shell cmd="${command}"
    endif
	- $(call print_completed_target)
.PHONY: $(UNMOUNT_TARGETS)
.SILENT: $(UNMOUNT_TARGETS)
$(UNMOUNT_TARGETS): 
	- $(call print_running_target)
	- $(eval name=$(@:unmount-%=%))
	- $(eval command=find $(BUILD_DIR)$(PSEP)$(name) -type d -exec umount -lvf {} \; || true)
    ifeq ($(DOCKER_ENV),true)
	- @$(MAKE) --no-print-directory \
	 -f $(THIS_FILE) shell \
	 docker_image="${BUILDER_IMAGE}" \
	 container_name="${BUILDER_CONTAINER_NAME}" \
	 mount_point="${BUILDER_CONTAINER_MOUNT_POINT} \
	 cmd="${command}"
    endif
    ifeq ($(DOCKER_ENV),false)
	- @$(MAKE) --no-print-directory \
	 -f $(THIS_FILE) shell cmd="${command}"
    endif
	- $(call print_completed_target)
.PHONY: $(CLEAN_TARGETS)
.SILENT: $(CLEAN_TARGETS)
$(CLEAN_TARGETS): $(UNMOUNT_TARGETS)
	- $(call print_running_target)
	- $(eval name=$(@:clean-%=%))
	- $(eval command=$(RM) $(BUILD_DIR)$(PSEP)$(name))
    ifeq ($(DOCKER_ENV),true)
	- @$(MAKE) --no-print-directory \
	 -f $(THIS_FILE) shell \
	 docker_image="${BUILDER_IMAGE}" \
	 container_name="${BUILDER_CONTAINER_NAME}" \
	 mount_point="${BUILDER_CONTAINER_MOUNT_POINT} \
	 cmd="${command}"
    endif
    ifeq ($(DOCKER_ENV),false)
	- @$(MAKE) --no-print-directory \
	 -f $(THIS_FILE) shell cmd="${command}"
    endif
	- $(call print_completed_target)
clean: 
	- $(call print_running_target)
	- @$(MAKE) --no-print-directory -f $(THIS_FILE) $(CLEAN_TARGETS)
	- $(call print_completed_target)
