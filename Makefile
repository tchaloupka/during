.PHONY: all

BUILD_DIR = build
SRC_FILES = -Isource/ source/during/*.d
TEST_FILES = -Itests/ tests/*.d
TEST_FLAGS = -debug -g -unittest -w -vcolumns
SILLY_DIR = ~/.dub/packages/silly/1.1.1/silly
SILLY_FILES = -I$(SILLY_DIR) $(SILLY_DIR)/silly.d

ifeq ($(DC),ldc2)
	DC=ldmd2
endif

$(SILLY_DIR):
	dub fetch silly --version="1.1.1"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

buildTestSilly: $(SILLY_DIR) | $(BUILD_DIR)
	$(DC) -of=$(BUILD_DIR)/during-test -version=test_root $(TEST_FLAGS) $(SRC_FILES) $(TEST_FILES) $(SILLY_FILES)

buildTest: | $(BUILD_DIR)
	$(DC) -of=$(BUILD_DIR)/during-test -version=test_root $(TEST_FLAGS) $(SRC_FILES) $(TEST_FILES)

test: buildTestSilly
	./$(BUILD_DIR)/during-test -t 1

testPlain: buildTest
	./$(BUILD_DIR)/during-test

buildTestBC: | $(BUILD_DIR)
	$(DC) -of=$(BUILD_DIR)/during-test-betterC $(TEST_FLAGS) -betterC $(SRC_FILES) $(TEST_FILES)

testBC: buildTestBC
	./$(BUILD_DIR)/during-test-betterC

buildCodecov: $(SILLY_DIR) | $(BUILD_DIR)
	$(DC) -of=$(BUILD_DIR)/during-test-codecov -version=test_root -cov $(TEST_FLAGS) $(SRC_FILES) $(TEST_FILES) $(SILLY_FILES)

codecov: buildCodecov
	./$(BUILD_DIR)/during-test-codecov | true

all: buildTest buildTestBC codecov

clean:
	- rm -rf $(BUILD_DIR)
	- rm -f *.a
	- rm -f *.o
	- rm -f *.dat
	- rm -f ./*.lst
