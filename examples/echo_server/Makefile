.PHONY: all

SRC_FILES = -Isource/ source/*.d
DURING_FILES = -I../../source/ ../../source/during/*.d
BUILD_FLAGS = -debug -g -unittest -w -vcolumns

ifeq ($(DC),ldc2)
	DC=ldmd2
endif

all: build

build:
	$(DC) -of=echo_server $(BUILD_FLAGS) -betterC $(SRC_FILES) $(DURING_FILES)

run: build
	./echo_server

clean:
	- rm -f echo_server*
