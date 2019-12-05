.PHONY: all

SRC_FILES = -Isource/ source/during/*.d
TEST_FILES = -Itests/ tests/*.d
TEST_FLAGS = -debug -g -unittest -w -vcolumns
SILLY_DIR = ~/.dub/packages/silly-1.0.0/silly
SILLY_FILES = -I$(SILLY_DIR) $(SILLY_DIR)/silly.d

ifeq ($(DC),ldc2)
	DC=ldmd2
endif

$(SILLY_DIR):
	dub fetch silly --version="1.0.0"

buildTestSilly: $(SILLY_DIR)
	$(DC) -of=during-test -version=test_root $(TEST_FLAGS) $(SRC_FILES) $(TEST_FILES) $(SILLY_FILES)

buildTest:
	$(DC) -of=during-test -version=test_root $(TEST_FLAGS) $(SRC_FILES) $(TEST_FILES)

test: buildTestSilly
	./during-test -t 1

testPlain: buildTest
	./during-test

buildTestBC:
	$(DC) -of=during-test-bc $(TEST_FLAGS) -betterC $(SRC_FILES) $(TEST_FILES)

testBC: buildTestBC
	./during-test-bc

buildCodecov: $(SILLY_DIR)
	$(DC) -of=during-test-codecov -version=test_root -cov $(TEST_FLAGS) $(SRC_FILES) $(TEST_FILES) $(SILLY_FILES)

codecov: buildCodecov
	./during-test-codecov | true

all: buildTest buildTestBC codecov

clean:
	- rm -f *.a
	- rm -f *.o
	- rm -f during-test*
	- rm -f *.dat
	- rm -f ./*.lst
