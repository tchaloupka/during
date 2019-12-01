#!/bin/sh

set -ex

# As dub sometimes sucks..
${DC} -of=during-test-unittest-bc -debug -g -unittest -w -betterC -vcolumns -Isource/ source/during/*.d source/during/tests/*.d
./during-test-unittest-bc
rm during-test-unittest-bc*
