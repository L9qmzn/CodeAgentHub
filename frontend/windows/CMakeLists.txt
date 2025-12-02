# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(cc_mobile LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "cc_mobile")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Copy backend files to build directory
set(BACKEND_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../release/backend")
set(BACKEND_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/backend")
set(CONFIG_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../backend/ts_backend")

# Create backend directory and copy all backend files
install(CODE "
  file(MAKE_DIRECTORY \"${BACKEND_INSTALL_DIR}\")

  # Copy esbuild-bundled backend (backend.js + node_modules)
  if(EXISTS \"${BACKEND_SOURCE_DIR}/backend.js\")
    message(STATUS \"Copying esbuild-bundled backend from ${BACKEND_SOURCE_DIR}\")

    # Copy backend.js
    file(COPY \"${BACKEND_SOURCE_DIR}/backend.js\"
         DESTINATION \"${BACKEND_INSTALL_DIR}\")

    # Copy config.yaml
    if(EXISTS \"${BACKEND_SOURCE_DIR}/config.yaml\")
      file(COPY \"${BACKEND_SOURCE_DIR}/config.yaml\"
           DESTINATION \"${BACKEND_INSTALL_DIR}\")
    endif()

    # Copy hide-windows-preload.js (Windows 窗口隐藏脚本)
    if(EXISTS \"${BACKEND_SOURCE_DIR}/hide-windows-preload.js\")
      file(COPY \"${BACKEND_SOURCE_DIR}/hide-windows-preload.js\"
           DESTINATION \"${BACKEND_INSTALL_DIR}\")
      message(STATUS \"  ✓ hide-windows-preload.js copied\")
    endif()

    # Copy node_modules (better-sqlite3, bindings, file-uri-to-path)
    if(EXISTS \"${BACKEND_SOURCE_DIR}/node_modules\")
      file(COPY \"${BACKEND_SOURCE_DIR}/node_modules\"
           DESTINATION \"${BACKEND_INSTALL_DIR}\")
    endif()

    message(STATUS \"✅ esbuild backend copied successfully\")
  else()
    message(WARNING \"No packaged backend found. Run 'npm run build:release' in backend/ts_backend first.\")
  endif()
  " COMPONENT Runtime)

# Copy launcher and environment check scripts
set(SCRIPTS_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
install(CODE "
  # Copy launcher.bat
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/launcher.bat\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/launcher.bat\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ launcher.bat copied\")
  endif()

  # Copy check_environment.bat
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/check_environment.bat\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/check_environment.bat\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ check_environment.bat copied\")
  endif()

  # Copy start_backend_debug.bat
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/start_backend_debug.bat\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/start_backend_debug.bat\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ start_backend_debug.bat copied\")
  endif()

  # Copy diagnose_backend.bat
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/diagnose_backend.bat\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/diagnose_backend.bat\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ diagnose_backend.bat copied\")
  endif()

  # Copy setup_environment.bat
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/setup_environment.bat\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/setup_environment.bat\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ setup_environment.bat copied\")
  endif()

  # Copy fix_all.bat (一键修复工具)
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/fix_all.bat\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/fix_all.bat\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ fix_all.bat copied\")
  endif()

  # Copy rebuild_native.bat (重新编译原生模块)
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/rebuild_native.bat\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/rebuild_native.bat\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ rebuild_native.bat copied\")
  endif()

  # Copy README_RELEASE.md
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/README_RELEASE.md\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/README_RELEASE.md\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    file(RENAME \"${CMAKE_INSTALL_PREFIX}/README_RELEASE.md\"
              \"${CMAKE_INSTALL_PREFIX}/README.md\")
    message(STATUS \"✅ README.md copied\")
  endif()

  # Copy START_HERE.txt
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/START_HERE.txt\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/START_HERE.txt\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ START_HERE.txt copied\")
  endif()

  # Copy TOOLS_GUIDE.md
  if(EXISTS \"${SCRIPTS_SOURCE_DIR}/TOOLS_GUIDE.md\")
    file(COPY \"${SCRIPTS_SOURCE_DIR}/TOOLS_GUIDE.md\"
         DESTINATION \"${CMAKE_INSTALL_PREFIX}\")
    message(STATUS \"✅ TOOLS_GUIDE.md copied\")
  endif()
  " COMPONENT Runtime)
