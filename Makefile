### Build Options ###

MAINEXE      := PSX.EXE
BINDIR       := COMMON/BIN/
COMPARE      ?= 1
NON_MATCHING ?= 0
VERBOSE      ?= 0
BUILD_DIR    ?= build

# NON_MATCHING=1 implies COMPARE=0
ifeq ($(NON_MATCHING),1)
override COMPARE=0
endif

ifeq ($(VERBOSE),0)
V := @
endif

### Tools ###

PYTHON := python3
SPLAT  := splat split
DIFF   := diff
DD     := dd

CROSS   := mips-linux-gnu-
AS      := $(CROSS)as -EL
LD      := $(CROSS)ld -EL
OBJCOPY := $(CROSS)objcopy
STRIP   := $(CROSS)strip
CPP     := $(CROSS)cpp
CC      :=

PRINT     := printf '
ENDCOLOR  := \033[0m
WHITE     := \033[0m
ENDWHITE  := $(ENDCOLOR)
GREEN     := \033[0;32m
ENDGREEN  := $(ENDCOLOR)
BLUE      := \033[0;34m
ENDBLUE   := $(ENDCOLOR)
YELLOW    := \033[0;33m
ENDYELLOW := $(ENDCOLOR)
PURPLE    := \033[0;35m
ENDPURPLE := $(ENDCOLOR)
ENDLINE   := \n'

### Compiler Options ###

ASFLAGS  := -Iinclude -march=r3000 -mtune=r3000 -no-pad-sections
CFLAGS   :=
CPPFLAGS :=
LDFLAGS  := --no-check-sections

ifeq ($(NON_MATCHING),1)
CPPFLAGS += -DNON_MATCHING
endif

### Sources ###

# Object files
MAIN_OBJ := $(shell grep -E 'BUILD_PATH.+\.o' ldscripts/main.ld -o | sed "s/BUILD_PATH/${BUILD_DIR}/g")
CONFIG_OBJ := $(shell grep -E 'BUILD_PATH.+\.o' ldscripts/config.ld -o | sed "s/BUILD_PATH/${BUILD_DIR}/g")
DEPENDS := $(MAIN_OBJ:=.d)
DEPENDS += $(CONFIG_OBJ:=.d)

-include $(DEPENDS)

### Targets ###

all: $(BUILD_DIR)/main.exe $(BUILD_DIR)/config.bin

clean:
	$(V)rm -rf $(BUILD_DIR)

distclean: clean
	$(V)rm -rf asm
	$(V)rm -rf ldscripts

split:
	$(V)$(SPLAT) config/main.yaml
	$(V)$(SPLAT) config/config.yaml

setup: distclean split

$(BUILD_DIR)/%.s.o: %.s
	@$(PRINT)$(GREEN)Assembling asm file: $(ENDGREEN)$(BLUE)$<$(ENDBLUE)$(ENDLINE)
	@mkdir -p $(shell dirname $@)
	$(V)$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/%.ld: ldscripts/%.ld
	@$(PRINT)$(GREEN)Preprocessing linker script: $(ENDGREEN)$(BLUE)$<$(ENDBLUE)$(ENDLINE)
	$(V)$(CPP) -P -DBUILD_PATH=$(BUILD_DIR) $< -o $@
#Temporary hack for noload segment wrong alignment
	@sed -r -i 's/\.main_bss \(NOLOAD\) : SUBALIGN\(4\)/.main_bss main_DATA_END (NOLOAD) : SUBALIGN(4)/g' $@

$(BUILD_DIR)/main.elf: $(MAIN_OBJ) $(BUILD_DIR)/main.ld
	@$(PRINT)$(GREEN)Linking main.elf file: $(ENDGREEN)$(BLUE)$@$(ENDBLUE)$(ENDLINE)
	$(V)$(LD) -T ldscripts/undefined_syms_auto.main.txt -T ldscripts/undefined_funcs_auto.main.txt -T $(BUILD_DIR)/main.ld -Map $(BUILD_DIR)/main.map $(LDFLAGS) -o $@

$(BUILD_DIR)/main.exe: $(BUILD_DIR)/main.elf
	@$(PRINT)$(GREEN)Creating main.exe: $(ENDGREEN)$(BLUE)$@$(ENDBLUE)$(ENDLINE)
	$(V)$(OBJCOPY) $< $@ -O binary
	$(V)$(OBJCOPY) -O binary --gap-fill 0x00 --pad-to 0xF1000 $< $@
	$(V)printf '\4' | dd of=build/main.exe bs=1 seek=985088 count=1 conv=notrunc status=none
ifeq ($(COMPARE),1)
	@$(DIFF) $(MAINEXE) $(BUILD_DIR)/main.exe && printf "OK\n" || (echo 'The build succeeded, but did not match the base PSX.EXE. This is expected if you are making changes to the game. To skip this check, use "make COMPARE=0".' && false)
endif

$(BUILD_DIR)/config.elf: $(CONFIG_OBJ) $(BUILD_DIR)/config.ld
	@$(PRINT)$(GREEN)Linking config.elf file: $(ENDGREEN)$(BLUE)$@$(ENDBLUE)$(ENDLINE)
	$(V)$(LD) -T ldscripts/undefined_syms_auto.config.txt -T ldscripts/undefined_funcs_auto.config.txt -T $(BUILD_DIR)/config.ld -Map $(BUILD_DIR)/config.map $(LDFLAGS) -o $@

$(BUILD_DIR)/config.bin: $(BUILD_DIR)/config.elf
	@$(PRINT)$(GREEN)Creating config.bin: $(ENDGREEN)$(BLUE)$@$(ENDBLUE)$(ENDLINE)
	$(V)$(OBJCOPY) $< $@ -O binary
	$(V)$(OBJCOPY) -O binary --gap-fill 0x00 --pad-to 0x61B0 $< $@
ifeq ($(COMPARE),1)
	@$(DIFF) $(BINDIR)/CONFIG.BIN $(BUILD_DIR)/config.bin && printf "OK\n" || (echo 'The build succeeded, but did not match the base CONFIG.BIN. This is expected if you are making changes to the game. To skip this check, use "make COMPARE=0".' && false)
endif

### Make Settings ###

.PHONY: all clean distclean setup split

# Remove built-in implicit rules to improve performance
MAKEFLAGS += --no-builtin-rules

# Print target for debugging
print-% : ; $(info $* is a $(flavor $*) variable set to [$($*)]) @true
