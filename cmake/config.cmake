# Contains the build settings that the Dependencies and Core targets share.
# Settings that are specific to the game belong to core_config instead.
add_library(deps_config INTERFACE)

# GeneralsX @build rpi5 19/10/2026 The DXVK source build (Raspberry Pi 5) clones DXVK at build time, and
# every target can include windows.h, which needs DXVK's include/native headers. Make all code that
# links deps_config wait until the DXVK sources are cloned and patched (not until DXVK is built).
if(TARGET dxvk_native_build-patch)
    add_dependencies(deps_config dxvk_native_build-patch)
endif()

add_library(core_config INTERFACE)

target_link_libraries(core_config INTERFACE deps_config)

include(${CMAKE_CURRENT_LIST_DIR}/config-build.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/config-macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/config-retail.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/config-debug.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/config-memory.cmake)
