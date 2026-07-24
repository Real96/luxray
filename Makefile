#---------------------------------------------------------------------------------
.SUFFIXES:
#---------------------------------------------------------------------------------

ifeq ($(strip $(DEVKITPRO)),)
$(error "Please set DEVKITPRO in your environment. export DEVKITPRO=<path to>/devkitpro")
endif

TOPDIR ?= $(CURDIR)
include $(DEVKITPRO)/libnx/switch_rules

#---------------------------------------------------------------------------------
# Luxray — updated for Atmosphere 1.11.x / HOS 22.x, devkitA64 (GCC 16), libnx >= 4.10.0
#
# libnx 4.10.0 is a hard floor: HOS 21.0.0 changed the userland<->kernel TLS ABI
# and anything built against older libnx corrupts memory. See MIGRATION.md §2.1.
#
# Knobs:
#   ENABLE_DEBUG=1     debug build (drops -DNDEBUG)
#   NO_EXCEPTIONS=0    re-enable C++ exceptions (default: off, see below)
#   BOOT2=1            ship flags/boot2.flag so the sysmodule autostarts at boot
#   COMPAT_SHIM=0      stop force-including include/lx_compat.h (default: on)
#---------------------------------------------------------------------------------

APP_TITLE   := Luxray
APP_TITLEID := 0100000000000195
APP_AUTHOR  := 3096
APP_VERSION := w0.2.0

TARGET   := luxray
BUILD    := build
INCLUDES := source include libs/libluxio/include libs/libluxio/lvgl/lvgl

ifneq ($(BUILD),$(notdir $(CURDIR)))
SOURCES  := $(shell find source libs/libluxio/src libs/libluxio/lvgl/lvgl/src -type d)
endif

DATA     := data
#ROMFS   := romfs

GITREV := $(shell git rev-parse HEAD 2>/dev/null | cut -c1-8)
ifneq ($(GITREV),)
APP_VERSION := $(APP_VERSION)-$(GITREV)
endif

NO_ICON       = TRUE
NO_EXCEPTIONS ?= 1
COMPAT_SHIM   ?= 1

# sha256sum is coreutils-only; macOS ships shasum
SHA256 := $(shell command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo "shasum -a 256")

#---------------------------------------------------------------------------------
# options for code generation
#---------------------------------------------------------------------------------
ARCH := -march=armv8-a+crc+crypto -mtune=cortex-a57 -mtp=soft -fPIE

# -fcommon: GCC 10 flipped the default to -fno-common, which breaks the
# tentative definitions in the vendored 2020-era LVGL. Remove once LVGL is
# upgraded or the offending globals are given a single definition.
CFLAGS := -g -Wall -O2 -ffunction-sections -fdata-sections -fcommon \
          $(ARCH) $(DEFINES) $(INCLUDE) -D__SWITCH__

ifeq ($(strip $(ENABLE_DEBUG)),)
CFLAGS += -DNDEBUG
endif

# Force-include the libnx 2.x/3.x compatibility shim into every translation
# unit, so the existing call sites (hidScanInput, KEY_A, pmshellLaunchProcess,
# fatalSimple, ...) compile unmodified against libnx 4.x. Scaffolding: port the
# call sites for real, then build with COMPAT_SHIM=0 and delete the header.
ifeq ($(COMPAT_SHIM),1)
CFLAGS += -include $(TOPDIR)/include/lx_compat.h
endif

CXXFLAGS := $(CFLAGS) -std=c++17 -fno-rtti

# C++ exceptions are implemented on top of TLS slots, which is precisely what
# HOS 21.0.0 broke, and unwinding tables are dead weight in a memory-starved
# sysmodule. Set NO_EXCEPTIONS=0 if the codebase actually uses try/catch.
ifeq ($(NO_EXCEPTIONS),1)
CXXFLAGS += -fno-exceptions
endif

ASFLAGS  := -g $(ARCH)
LDFLAGS   = -specs=$(DEVKITPRO)/libnx/switch.specs -g $(ARCH) \
            -Wl,--gc-sections -Wl,-Map,$(notdir $*.map)

LIBS := -lnx

#---------------------------------------------------------------------------------
# list of directories containing libraries, this must be the top level containing
# include and lib
#---------------------------------------------------------------------------------
LIBDIRS := $(PORTLIBS) $(LIBNX)

#---------------------------------------------------------------------------------
# no real need to edit anything past this point unless you need to add additional
# rules for different file extensions
#---------------------------------------------------------------------------------
ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------

export OUTPUT  := $(CURDIR)/$(TARGET)
export TOPDIR  := $(CURDIR)

export VPATH   := $(foreach dir,$(SOURCES),$(CURDIR)/$(dir)) \
                  $(foreach dir,$(DATA),$(CURDIR)/$(dir))

export DEPSDIR := $(CURDIR)/$(BUILD)

CFILES   := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.c)))
CPPFILES := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.cpp)))
SFILES   := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.s)))
BINFILES := $(foreach dir,$(DATA),$(notdir $(wildcard $(dir)/*.*)))

#---------------------------------------------------------------------------------
# use CXX for linking C++ projects, CC for standard C
#---------------------------------------------------------------------------------
ifeq ($(strip $(CPPFILES)),)
export LD := $(CC)
else
export LD := $(CXX)
endif

export OFILES_BIN := $(addsuffix .o,$(BINFILES))
export OFILES_SRC := $(CPPFILES:.cpp=.o) $(CFILES:.c=.o) $(SFILES:.s=.o)
export OFILES     := $(OFILES_BIN) $(OFILES_SRC)
export HFILES_BIN := $(addsuffix .h,$(subst .,_,$(BINFILES)))

export INCLUDE := $(foreach dir,$(INCLUDES),-I$(CURDIR)/$(dir)) \
                  $(foreach dir,$(LIBDIRS),-I$(dir)/include) \
                  -I$(CURDIR)/$(BUILD)

export LIBPATHS := $(foreach dir,$(LIBDIRS),-L$(dir)/lib)

ifeq ($(strip $(CONFIG_JSON)),)
	jsons := $(wildcard *.json)
	ifneq (,$(findstring $(TARGET).json,$(jsons)))
		export APP_JSON := $(TOPDIR)/$(TARGET).json
	else
		ifneq (,$(findstring config.json,$(jsons)))
			export APP_JSON := $(TOPDIR)/config.json
		endif
	endif
else
	export APP_JSON := $(TOPDIR)/$(CONFIG_JSON)
endif

ifeq ($(strip $(ICON)),)
	icons := $(wildcard *.jpg)
	ifneq (,$(findstring $(TARGET).jpg,$(icons)))
		export APP_ICON := $(TOPDIR)/$(TARGET).jpg
	else
		ifneq (,$(findstring icon.jpg,$(icons)))
			export APP_ICON := $(TOPDIR)/icon.jpg
		endif
	endif
else
	export APP_ICON := $(TOPDIR)/$(ICON)
endif

ifeq ($(strip $(NO_ICON)),)
	export NROFLAGS += --icon=$(APP_ICON)
endif

ifeq ($(strip $(NO_NACP)),)
	export NROFLAGS += --nacp=$(CURDIR)/$(TARGET).nacp
endif

ifneq ($(APP_TITLEID),)
	export NACPFLAGS += --titleid=$(APP_TITLEID)
endif

ifneq ($(ROMFS),)
	export NROFLAGS += --romfsdir=$(CURDIR)/$(ROMFS)
endif

.PHONY: all $(BUILD) debug zip release clean check-toolchain

#---------------------------------------------------------------------------------
all: $(BUILD)

# Fails loudly on a pre-4.0 libnx instead of drowning the user in a few hundred
# "KEY_A undeclared" errors.
check-toolchain:
	@grep -rqs "HidNpadButton_A" $(LIBNX)/include || \
	 ( echo ""; \
	   echo "  ERROR: libnx is too old (pre-4.0 HID API detected)."; \
	   echo "  Luxray requires libnx >= 4.10.0 for Atmosphere 1.10+ / HOS 21+."; \
	   echo "  Run: sudo dkp-pacman -Syu switch-dev switch-tools"; \
	   echo ""; exit 1 )

$(BUILD): check-toolchain
	@[ -d $@ ] || mkdir -p $@
	@$(MAKE) --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile

#---------------------------------------------------------------------------------
debug:
	@$(MAKE) all --no-print-directory ENABLE_DEBUG=true

#---------------------------------------------------------------------------------
TEMP_DIR     = release/tmp
TEMP_DIR_OVL = release/tmp-ovl

zip:
	@$(MAKE) clean --no-print-directory
	@$(MAKE) all --no-print-directory
ifneq ($(strip $(APP_JSON)),)
	@mkdir -p $(TEMP_DIR)/atmosphere/contents/$(APP_TITLEID)/
	@cp $(TARGET).nsp $(TEMP_DIR)/atmosphere/contents/$(APP_TITLEID)/exefs.nsp
	@[ -f toolbox.json ] && cp toolbox.json $(TEMP_DIR)/atmosphere/contents/$(APP_TITLEID)/ || true
ifeq ($(BOOT2),1)
	@mkdir -p $(TEMP_DIR)/atmosphere/contents/$(APP_TITLEID)/flags/
	@touch $(TEMP_DIR)/atmosphere/contents/$(APP_TITLEID)/flags/boot2.flag
endif
	@cp LICENSE $(TEMP_DIR)/
	@cd $(TEMP_DIR)/; zip tmp.zip LICENSE atmosphere -r
endif
	@mkdir -p $(TEMP_DIR_OVL)/switch/.overlays/
	@cp $(TARGET).nro $(TEMP_DIR_OVL)/switch/.overlays/$(TARGET).ovl
	@cp LICENSE $(TEMP_DIR_OVL)/
	@cd $(TEMP_DIR_OVL)/; zip tmp.zip LICENSE switch -r

#---------------------------------------------------------------------------------
release: zip
	$(eval RELEASE_DIR = release/$(TARGET)-$(APP_VERSION)-$(shell $(SHA256) $(TARGET).elf | cut -d " " -f 1))
	@mkdir -p $(RELEASE_DIR)
	cp $(TARGET).elf $(RELEASE_DIR)
ifneq ($(strip $(APP_JSON)),)
	$(eval RELEASE_HASH = $(shell $(SHA256) release/tmp/tmp.zip | cut -d " " -f 1))
	mv $(TEMP_DIR)/tmp.zip $(RELEASE_DIR)/$(TARGET)-$(APP_VERSION)_$(RELEASE_HASH).zip
	@rm -r $(TEMP_DIR)/
endif
	$(eval RELEASE_HASH = $(shell $(SHA256) $(TEMP_DIR_OVL)/tmp.zip | cut -d " " -f 1))
	mv $(TEMP_DIR_OVL)/tmp.zip $(RELEASE_DIR)/$(TARGET)-ovlloader-$(APP_VERSION)_$(RELEASE_HASH).zip
	@rm -r $(TEMP_DIR_OVL)/

#---------------------------------------------------------------------------------
clean:
	@echo clean ...
	@rm -fr $(BUILD) $(TARGET).nro $(TARGET).nacp $(TARGET).elf
ifneq ($(strip $(APP_JSON)),)
	@rm -fr $(BUILD) $(TARGET).nsp $(TARGET).nso $(TARGET).npdm
endif

#---------------------------------------------------------------------------------
else
.PHONY: all

DEPENDS := $(OFILES:.o=.d)

#---------------------------------------------------------------------------------
# main targets
#---------------------------------------------------------------------------------
ifeq ($(strip $(APP_JSON)),)
all : $(OUTPUT).nro
else
all : $(OUTPUT).nro $(OUTPUT).nsp
endif

ifeq ($(strip $(NO_NACP)),)
$(OUTPUT).nro : $(OUTPUT).elf $(OUTPUT).nacp
else
$(OUTPUT).nro : $(OUTPUT).elf
endif

$(OUTPUT).nsp : $(OUTPUT).nso $(OUTPUT).npdm
$(OUTPUT).nso : $(OUTPUT).elf
$(OUTPUT).elf : $(OFILES)

$(OFILES_SRC) : $(HFILES_BIN)

#---------------------------------------------------------------------------------
# you need a rule like this for each extension you use as binary data
#---------------------------------------------------------------------------------
%.bin.o %_bin.h : %.bin
#---------------------------------------------------------------------------------
	@echo $(notdir $<)
	@$(bin2o)

-include $(DEPENDS)

#---------------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------------
