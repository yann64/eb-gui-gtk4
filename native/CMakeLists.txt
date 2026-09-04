# Standalone build for eb-gui-gtk4's tiny native trampoline - not
# ebpm/ebc-driven, matching eb-qt6/eb-haiku's own native/CMakeLists.txt
# precedent. Produces libebguigtk4.a - see this package's own README
# "Building" section for the exact `-l`/`-I` flags a consumer needs
# alongside eb-gtk4's own.
#
# Build:
#   cmake -S native -B native/build
#   cmake --build native/build

cmake_minimum_required(VERSION 3.16)
project(ebguigtk4 CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK4 REQUIRED IMPORTED_TARGET gtk4)

add_library(ebguigtk4 STATIC
    shim_closecallback.cpp
    shim_actiontrigger.cpp
    shim_userdatasignal.cpp
)
target_include_directories(ebguigtk4 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(ebguigtk4 PUBLIC PkgConfig::GTK4)
