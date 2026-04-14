# GenerateBuildTime.cmake
# Invoked via cmake -P at build time (PRE_BUILD) so the timestamp reflects the
# actual compile time rather than the last cmake configure run.
#
# Variables expected from the caller (passed with -D):
#   OUTPUT_FILE  — full path to the AppBuildTime.h to write
#
string(TIMESTAMP BUILD_TIME "%Y-%m-%d %H:%M UTC" UTC)
string(TIMESTAMP BUILD_DATE "%Y-%m-%d" UTC)

file(WRITE "${OUTPUT_FILE}"
"#pragma once
// Auto-generated at build time by cmake/GenerateBuildTime.cmake.
// Do not edit — changes will be overwritten on the next build.
#define STELLAR_BUILD_TIME \"${BUILD_TIME}\"
#define STELLAR_BUILD_DATE \"${BUILD_DATE}\"
")
