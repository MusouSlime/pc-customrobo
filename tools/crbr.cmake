# The port's targets, included by the generated build with
# -DWIIKIT_EXTRA=<this file>: the game's own layer linked into wiiboot.
target_sources(wiiboot PRIVATE ${CMAKE_CURRENT_LIST_DIR}/crbr.cpp)

# A test of wiikit's memory card: it drives the EXI's registers the way the
# SDK drives them, and checks that what it wrote is in the card's file.
add_executable(memcard_test ${CMAKE_CURRENT_LIST_DIR}/memcard_test.cpp)
target_link_libraries(memcard_test wiikit_core wiikit_hw recomp)
