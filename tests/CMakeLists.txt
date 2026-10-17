set(CMAKE_TEST_OUTPUT ${CMAKE_BINARY_DIR})
set(CMAKE_TEST_COMPONENT_OUTPUT ${CMAKE_BINARY_DIR}/generated/test_component)

if (NOT EXISTS ${CMAKE_TEST_COMPONENT_OUTPUT})
  file(MAKE_DIRECTORY ${CMAKE_TEST_COMPONENT_OUTPUT})
endif()

# workaround for swiftc hang: https://linear.app/the-browser-company/issue/WIN-96/fix-swiftc-hanging-on-ci-machines
if ($ENV{NUMBER_OF_PROCESSORS} EQUAL 64)
  set(SWIFT_BUILD_ARGS ${SWIFT_BUILD_ARGS} -j 8)
else()
  set(SWIFT_BUILD_ARGS ${SWIFT_BUILD_ARGS} -j $ENV{NUMBER_OF_PROCESSORS})
endif()

# SPM requires build config to be in lower case
string(TOLOWER ${CMAKE_BUILD_TYPE} SPM_BUILD_CONFIG)
set(SWIFT_BUILD_ARGS ${SWIFT_BUILD_ARGS} -c ${SPM_BUILD_CONFIG})

# Output to the cmake binary dir so build outputs are consolidated
set(SWIFT_BUILD_ARGS ${SWIFT_BUILD_ARGS} --scratch-path ${CMAKE_CURRENT_BINARY_DIR})

# PDB debug info for Swift targets (for ETW profiling with xperf/WPA)
if(SWIFT_DEBUG_MODE STREQUAL "pdb")
  set(SWIFT_BUILD_ARGS ${SWIFT_BUILD_ARGS} -Xswiftc -g -Xswiftc -debug-info-format=codeview -Xlinker -debug)
endif()

# CI machines have path issues so we pass the path to swift as part of configure
if (DEFINED SWIFT_EXE)
  set(SWIFT_COMMAND ${SWIFT_EXE} build ${SWIFT_BUILD_ARGS})
else()
  set(SWIFT_COMMAND swift build ${SWIFT_BUILD_ARGS})
endif()

# The layout SwiftPM uses inside the scratch path changed across toolchain versions
# (6.3 moved products to out/Products/<config>-windows-<arch> from <triple>/<config>),
# so ask SwiftPM where it puts products instead of hardcoding the layout.
if (DEFINED SWIFT_EXE)
  set(SWIFT_SHOW_BIN_COMMAND ${SWIFT_EXE} build --show-bin-path ${SWIFT_BUILD_ARGS})
else()
  set(SWIFT_SHOW_BIN_COMMAND swift build --show-bin-path ${SWIFT_BUILD_ARGS})
endif()
execute_process(
  COMMAND ${SWIFT_SHOW_BIN_COMMAND}
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  RESULT_VARIABLE SPM_SHOW_BIN_RESULT
  OUTPUT_VARIABLE SPM_BIN_DIR
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT SPM_SHOW_BIN_RESULT EQUAL 0)
  message(FATAL_ERROR "Failed to query the SwiftPM build output directory (${SWIFT_SHOW_BIN_COMMAND})")
endif()
# swift prints a native path (backslashes); normalize so it round-trips through
# generated install scripts, which reject invalid character escapes like '\s'
string(REPLACE "\\" "/" SPM_BIN_DIR "${SPM_BIN_DIR}")

add_custom_target(test_app ALL
  COMMAND ${SWIFT_COMMAND}
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "Running Swift build..."
  BYPRODUCTS ${SPM_BIN_DIR}/test_app.exe
  DEPENDS GenerateBindings
  VERBATIM
)

# install is used to copy the built binaries and dependencies to a known location
# where they can be run from and isn't used for distribution
install(FILES ${SPM_BIN_DIR}/test_app.exe DESTINATION bin)
install(FILES ${SPM_BIN_DIR}/test_component.dll DESTINATION bin)

add_subdirectory(test_component)
add_subdirectory(test_app)