# Tries, in order:
# 1. A proper installed CMake package (LibtorrentRasterbarConfig.cmake)
# 2. pkg-config on Unix-like systems
# 3. Manual discovery rooted at LIBTORRENT_ROOT / ENV{LIBTORRENT_ROOT}
#
# Exposes:
#   LibtorrentRasterbar_FOUND
#   LibtorrentRasterbar_VERSION
#   LibtorrentRasterbar_INCLUDE_DIRS
#   LibtorrentRasterbar_LIBRARIES
#   target LibtorrentRasterbar::torrent-rasterbar

set(_LIBTORRENT_FIND_VERSION "${LibtorrentRasterbar_FIND_VERSION}")

if(NOT DEFINED LIBTORRENT_ROOT AND DEFINED ENV{LIBTORRENT_ROOT})
    set(LIBTORRENT_ROOT "$ENV{LIBTORRENT_ROOT}")
endif()

set(_libtorrent_hints)
if(LIBTORRENT_ROOT)
    list(APPEND _libtorrent_hints "${LIBTORRENT_ROOT}")
endif()

if(NOT LibtorrentRasterbar_FIND_COMPONENTS)
    set(LibtorrentRasterbar_FIND_COMPONENTS torrent-rasterbar)
endif()

find_package(LibtorrentRasterbar CONFIG QUIET
    HINTS ${_libtorrent_hints}
    PATH_SUFFIXES lib/cmake/LibtorrentRasterbar cmake/LibtorrentRasterbar
)

if(TARGET LibtorrentRasterbar::torrent-rasterbar)
    if(NOT LibtorrentRasterbar_FOUND)
        set(LibtorrentRasterbar_FOUND TRUE)
    endif()

    get_target_property(_libtorrent_include_dirs
        LibtorrentRasterbar::torrent-rasterbar INTERFACE_INCLUDE_DIRECTORIES)
    if(_libtorrent_include_dirs)
        set(LibtorrentRasterbar_INCLUDE_DIRS "${_libtorrent_include_dirs}")
    endif()

    set(LibtorrentRasterbar_LIBRARIES LibtorrentRasterbar::torrent-rasterbar)
    return()
endif()

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(PC_LIBTORRENT QUIET libtorrent-rasterbar)
endif()

find_path(LibtorrentRasterbar_INCLUDE_DIR
    NAMES libtorrent/version.hpp
    HINTS
        ${_libtorrent_hints}
        ${PC_LIBTORRENT_INCLUDEDIR}
        ${PC_LIBTORRENT_INCLUDE_DIRS}
    PATH_SUFFIXES include
)

find_library(LibtorrentRasterbar_LIBRARY
    NAMES torrent-rasterbar libtorrent-rasterbar rasterbar
    HINTS
        ${_libtorrent_hints}
        ${PC_LIBTORRENT_LIBDIR}
        ${PC_LIBTORRENT_LIBRARY_DIRS}
    PATH_SUFFIXES lib lib64
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(LibtorrentRasterbar
    REQUIRED_VARS LibtorrentRasterbar_INCLUDE_DIR LibtorrentRasterbar_LIBRARY
    VERSION_VAR PC_LIBTORRENT_VERSION
)

if(LibtorrentRasterbar_FOUND AND NOT TARGET LibtorrentRasterbar::torrent-rasterbar)
    add_library(LibtorrentRasterbar::torrent-rasterbar UNKNOWN IMPORTED)
    set_target_properties(LibtorrentRasterbar::torrent-rasterbar PROPERTIES
        IMPORTED_LOCATION "${LibtorrentRasterbar_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${LibtorrentRasterbar_INCLUDE_DIR}"
    )

    if(PC_LIBTORRENT_LINK_LIBRARIES)
        set_property(TARGET LibtorrentRasterbar::torrent-rasterbar APPEND PROPERTY
            INTERFACE_LINK_LIBRARIES "${PC_LIBTORRENT_LINK_LIBRARIES}")
    elseif(PC_LIBTORRENT_LIBRARIES)
        set_property(TARGET LibtorrentRasterbar::torrent-rasterbar APPEND PROPERTY
            INTERFACE_LINK_LIBRARIES "${PC_LIBTORRENT_LIBRARIES}")
    endif()
endif()

if(LibtorrentRasterbar_FOUND)
    set(LibtorrentRasterbar_INCLUDE_DIRS "${LibtorrentRasterbar_INCLUDE_DIR}")
    set(LibtorrentRasterbar_LIBRARIES LibtorrentRasterbar::torrent-rasterbar)
endif()

mark_as_advanced(
    LibtorrentRasterbar_INCLUDE_DIR
    LibtorrentRasterbar_LIBRARY
)
