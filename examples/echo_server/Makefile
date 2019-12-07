.PHONY: all

SRC_FILES = -Isource/ source/*.d
DURING_FILES = -I../../source/ ../../source/during/*.d
DEBUG_FLAGS = -debug -g -w -vcolumns
RELEASE_FLAGS = -O -release -inline -noboundscheck
MEMPOOLED_DIR = ~/.dub/packages/mempooled-0.1.1/mempooled
MEMPOOLED_FILES = $(MEMPOOLED_DIR)/source/mempooled/fixed.d

ifeq ($(DC),ldc2)
	DC=ldmd2
endif

all: build

build: $(MEMPOOLED_DIR)
	$(DC) -of=echo_server $(DEBUG_FLAGS) -betterC $(SRC_FILES) $(DURING_FILES) $(MEMPOOLED_FILES)

release: $(MEMPOOLED_DIR)
	$(DC) -of=echo_server $(RELEASE_FLAGS) -betterC $(SRC_FILES) $(DURING_FILES) $(MEMPOOLED_FILES)

run: build
	./echo_server

clean:
	- rm -f echo_server*

$(MEMPOOLED_DIR):
	dub fetch mempooled --version="0.1.2"
