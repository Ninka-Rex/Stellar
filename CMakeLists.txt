cmake_minimum_required(VERSION 3.25)
project(Stellar VERSION 0.6.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

option(ENABLE_LIBTORRENT "Enable libtorrent integration scaffolding" ON)
option(ENABLE_MAXMINDDB "Enable MMDB city lookup support" ON)

set(_stellar_default_libtorrent_source "")
if(EXISTS "${CMAKE_SOURCE_DIR}/third_party/libtorrent-rasterbar-2.0.12/CMakeLists.txt")
    set(_stellar_default_libtorrent_source
        "${CMAKE_SOURCE_DIR}/third_party/libtorrent-rasterbar-2.0.12")
endif()

if(ENABLE_MAXMINDDB AND EXISTS "${CMAKE_SOURCE_DIR}/third_party/libmaxminddb/CMakeLists.txt")
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(BUILD_FUZZING OFF CACHE BOOL "" FORCE)
    set(MAXMINDDB_BUILD_BINARIES OFF CACHE BOOL "" FORCE)
    set(MAXMINDDB_INSTALL OFF CACHE BOOL "" FORCE)
    add_subdirectory("${CMAKE_SOURCE_DIR}/third_party/libmaxminddb"
                     "${CMAKE_BINARY_DIR}/_deps/libmaxminddb")
endif()

set(LIBTORRENT_SOURCE_DIR "${_stellar_default_libtorrent_source}" CACHE PATH
    "Path to a libtorrent source tree to build as part of this project")

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Network
    Quick
    QuickControls2
    QuickDialogs2
    Widgets
    Concurrent
)

qt_standard_project_setup(REQUIRES 6.8)

if(ENABLE_LIBTORRENT)
    if(LIBTORRENT_SOURCE_DIR)
        if(EXISTS "${LIBTORRENT_SOURCE_DIR}/CMakeLists.txt")
            set(libtorrent_build_examples OFF CACHE BOOL "" FORCE)
            set(libtorrent_build_tests OFF CACHE BOOL "" FORCE)
            set(libtorrent_build_tools OFF CACHE BOOL "" FORCE)
            set(deprecated-functions OFF CACHE BOOL "" FORCE)
            cmake_policy(PUSH)
            if(POLICY CMP0183)
                cmake_policy(SET CMP0183 OLD)
            endif()
            if(POLICY CMP0167)
                cmake_policy(SET CMP0167 OLD)
            endif()
            add_subdirectory("${LIBTORRENT_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/_deps/libtorrent")
            cmake_policy(POP)
            if(TARGET torrent-rasterbar AND NOT TARGET LibtorrentRasterbar::torrent-rasterbar)
                add_library(LibtorrentRasterbar::torrent-rasterbar ALIAS torrent-rasterbar)
            endif()
            if(TARGET LibtorrentRasterbar::torrent-rasterbar)
                set(LibtorrentRasterbar_FOUND TRUE)
                message(STATUS "Libtorrent enabled from source tree: ${LIBTORRENT_SOURCE_DIR}")
            else()
                message(WARNING
                    "LIBTORRENT_SOURCE_DIR was set, but no torrent-rasterbar target was created. "
                    "Stellar will continue without libtorrent.")
            endif()
        else()
            message(WARNING
                "LIBTORRENT_SOURCE_DIR does not contain a CMakeLists.txt: ${LIBTORRENT_SOURCE_DIR}. "
                "Stellar will continue without libtorrent.")
        endif()
    else()
        find_package(LibtorrentRasterbar QUIET)
    endif()

    if(LibtorrentRasterbar_FOUND)
        message(STATUS "Libtorrent enabled: ${LibtorrentRasterbar_VERSION}")
    else()
        message(STATUS
            "Libtorrent integration requested, but the library was not found. "
            "Set LIBTORRENT_SOURCE_DIR, LIBTORRENT_ROOT, or LibtorrentRasterbar_DIR before configuring to enable it.")
    endif()
endif()

# ── Version header (configure time — version numbers only) ────────────────────
configure_file(app/src/AppVersion.h.in
               ${CMAKE_BINARY_DIR}/AppVersion.h
               @ONLY)

# ── Build timestamp (regenerated every build, not just every configure) ────────
# cmake -P runs GenerateBuildTime.cmake as a PRE_BUILD step so the date in the
# About page always matches the actual compile date, not the last cmake run.
set(STELLAR_BUILD_TIME_HEADER "${CMAKE_BINARY_DIR}/AppBuildTime.h")
add_custom_target(StellarBuildTime ALL
    COMMAND ${CMAKE_COMMAND}
        -DOUTPUT_FILE=${STELLAR_BUILD_TIME_HEADER}
        -P ${CMAKE_SOURCE_DIR}/cmake/GenerateBuildTime.cmake
    COMMENT "Updating build timestamp..."
)

# ── Sources ────────────────────────────────────────────────────────────────────
set(BACKEND_SOURCES
    app/src/main.cpp
    app/src/AppController.cpp
    app/src/DownloadItem.cpp
    app/src/DownloadQueue.cpp
    app/src/SegmentedTransfer.cpp
    app/src/NativeMessagingHost.cpp
    app/src/CategoryModel.cpp
    app/src/DownloadTableModel.cpp
    app/src/AppSettings.cpp
    app/src/StellarPaths.cpp
    app/src/SystemTrayIcon.cpp
    app/src/DownloadDatabase.cpp
    app/src/GrabberCrawler.cpp
    app/src/GrabberProjectModel.cpp
    app/src/YtdlpManager.cpp
    app/src/YtdlpTransfer.cpp
    app/src/GrabberResultModel.cpp
    app/src/Queue.cpp
    app/src/QueueDatabase.cpp
    app/src/QueueModel.cpp
    app/src/RssArticleModel.cpp
    app/src/RssFeedModel.cpp
    app/src/RssManager.cpp
    app/src/FileDragDropHelper.cpp
    app/src/TorrentSessionManager.cpp
    app/src/TorrentFileModel.cpp
    app/src/TorrentPeerModel.cpp
    app/src/TorrentTrackerModel.cpp
    app/src/TorrentSearchPluginModel.cpp
    app/src/TorrentSearchResultModel.cpp
    app/src/TorrentSearchManager.cpp
)

set(BACKEND_HEADERS
    app/src/AppController.h
    app/src/DownloadItem.h
    app/src/DownloadQueue.h
    app/src/SegmentedTransfer.h
    app/src/NativeMessagingHost.h
    app/src/CategoryModel.h
    app/src/DownloadTableModel.h
    app/src/AppSettings.h
    app/src/StellarPaths.h
    app/src/SystemTrayIcon.h
    app/src/DownloadDatabase.h
    app/src/GrabberCrawler.h
    app/src/GrabberProjectModel.h
    app/src/YtdlpManager.h
    app/src/YtdlpTransfer.h
    app/src/GrabberResultModel.h
    app/src/Queue.h
    app/src/QueueDatabase.h
    app/src/QueueModel.h
    app/src/RssArticleModel.h
    app/src/RssFeedModel.h
    app/src/RssManager.h
    app/src/FileDragDropHelper.h
    app/src/FileIconImageProvider.h
    app/src/TorrentSessionManager.h
    app/src/TorrentFileModel.h
    app/src/TorrentPeerModel.h
    app/src/TorrentTrackerModel.h
    app/src/TorrentSearchPluginModel.h
    app/src/TorrentSearchResultModel.h
    app/src/TorrentSearchManager.h
)

# ── QML Resources ──────────────────────────────────────────────────────────────
if(WIN32)
    list(APPEND BACKEND_SOURCES app/stellar.rc)
endif()

qt_add_executable(Stellar ${BACKEND_SOURCES} ${BACKEND_HEADERS})

qt_add_qml_module(Stellar
    URI com.stellar.app
    VERSION 1.0
    QML_FILES
        app/qml/Main.qml
        app/qml/Toolbar.qml
        app/qml/Sidebar.qml
        app/qml/DownloadTable.qml
        app/qml/StatusBar.qml
        app/qml/AddUrlDialog.qml
        app/qml/ToolbarBtn.qml
        app/qml/ToolbarDropdown.qml
        app/qml/DownloadProgressDialog.qml
        app/qml/DownloadCompleteDialog.qml
        app/qml/DeleteConfirmDialog.qml
        app/qml/DownloadFileInfoDialog.qml
        app/qml/SettingsDialog.qml
        app/qml/TrayMenuItem.qml
        app/qml/DuplicateDownloadDialog.qml
        app/qml/AddExceptionDialog.qml
        app/qml/BrowserIntegrationDialog.qml
        app/qml/SchedulerDialog.qml
        app/qml/FilePropertiesDialog.qml
        app/qml/FindDialog.qml
        app/qml/ColumnsDialog.qml
        app/qml/DeleteDoneConfirmDialog.qml
        app/qml/BatchDownloadDialog.qml
        app/qml/BatchDownloadListDialog.qml
        app/qml/GrabberDialog.qml
        app/qml/GrabberResultsDialog.qml
        app/qml/GrabberProjectPickerDialog.qml
        app/qml/GrabberSettingsDialog.qml
        app/qml/GrabberScheduleDialog.qml
        app/qml/GrabberStatisticsDialog.qml
        app/qml/GrabberIncludeFiltersDialog.qml
        app/qml/QueueSelectionDialog.qml
        app/qml/YtdlpDialog.qml
        app/qml/TorrentMetadataDialog.qml
        app/qml/TorrentSpeedLimitDialog.qml
        app/qml/DlgButton.qml
        app/qml/RssWindow.qml
        app/qml/RssDownloadRulesDialog.qml
        app/qml/TorrentSearchWindow.qml
        app/qml/TorrentSearchPluginsDialog.qml
        app/qml/TorrentSearchInstallDialog.qml
    RESOURCES
        app/qml/icons/add.svg
        app/qml/icons/resume.svg
        app/qml/icons/stop.svg
        app/qml/icons/delete.svg
        app/qml/icons/settings.svg
        app/qml/icons/gear.ico
        app/qml/icons/add_url.ico
        app/qml/icons/files_x.png
        app/qml/icons/pause_purple.png
        app/qml/icons/resume_purple.png
        app/qml/icons/pause_orange.png
        app/qml/icons/Tools.ico
        app/qml/icons/x_square.ico
        app/qml/icons/download.ico
        app/qml/icons/resume.ico
        app/qml/icons/pause.ico
        app/qml/icons/stop.ico
        app/qml/icons/delete.ico
        app/qml/icons/remove.ico
        app/qml/icons/properties.ico
        app/qml/icons/downloads.ico
        app/qml/icons/scheduler.png
        app/qml/icons/help.ico
        app/qml/icons/update.png
        app/qml/icons/clock.png
        app/qml/icons/arrow_down.png
        app/qml/icons/arrow_up.ico
        app/qml/icons/rename.ico
        app/qml/icons/new_file.ico
        app/qml/icons/arrow_right.ico
        app/qml/icons/arrow_left.ico
        app/qml/icons/exit.ico
        app/qml/icons/add.ico
        app/qml/icons/wand.ico
        app/qml/icons/search.ico
        app/qml/icons/rss.png
        app/qml/icons/cancel.ico
        app/qml/icons/copy.ico
        app/qml/icons/paste.ico
        app/qml/icons/copy_file.ico
        app/qml/icons/move_file.ico
        app/qml/icons/milky-way.png
        app/qml/icons/milky-way.ico
        app/qml/icons/milky-way.gif
        app/scripts/torrent_search_runner.py
        app/search_plugins/bitsearch.py
        app/search_plugins/limetorrents.py
        app/search_plugins/piratebay.py
        app/search_plugins/linuxtracker.py
        app/search_plugins/torrentproject.py
        app/search_plugins/torrentscsv.py
        app/qml/icons/torrent-client-logos/biglybt.png
        app/qml/icons/torrent-client-logos/bitcomet.png
        app/qml/icons/torrent-client-logos/BitLord_logo_2022.png
        app/qml/icons/torrent-client-logos/bittorrent.png
        app/qml/icons/torrent-client-logos/deluge.png
        app/qml/icons/torrent-client-logos/elementum.png
        app/qml/icons/torrent-client-logos/FDM.png
        app/qml/icons/torrent-client-logos/folx.png
        app/qml/icons/torrent-client-logos/frostwire.png
        app/qml/icons/torrent-client-logos/ktorrent.png
        app/qml/icons/torrent-client-logos/libretorrent.png
        app/qml/icons/torrent-client-logos/Libtorrent-rasterbar-logo.png
        app/qml/icons/torrent-client-logos/MediaGet2.png
        app/qml/icons/torrent-client-logos/picotorrent.png
        app/qml/icons/torrent-client-logos/qbittorrent.png
        app/qml/icons/torrent-client-logos/tixati-icon.png
        app/qml/icons/torrent-client-logos/transmission.png
        app/qml/icons/torrent-client-logos/utorrent.png
        app/qml/icons/torrent-client-logos/vuze.png
        app/qml/icons/torrent-client-logos/XunLei.png
        app/qml/icons/folder.ico
        app/qml/icons/arrow_download.ico
        app/qml/icons/scheduler2.ico
        app/qml/icons/folderdocuments.ico
        app/qml/icons/foldermusic.ico
        app/qml/icons/folderpictures.ico
        app/qml/icons/foldervideos.ico
        app/qml/icons/add_url.png
        app/qml/icons/resume.png
        app/qml/icons/pause.png
        app/qml/icons/exit.png
        app/qml/icons/delete.png
        app/qml/icons/remove.png
        app/qml/icons/gear.png
        app/qml/icons/download.png
        app/qml/icons/checkmark.png
        app/qml/icons/queues.png
        app/qml/icons/main_queue.png
        app/qml/icons/custom_queue.png
        app/qml/icons/synch_queue.png
        app/qml/icons/globe.png
        app/qml/icons/world-map.svg
        app/qml/icons/page.ico
        app/qml/icons/cloud_copylink.ico
        app/qml/icons/folder_view.ico
        app/qml/icons/about.ico
        app/qml/icons/torrent-categories/all_torrents.png
        app/qml/icons/torrent-categories/active.png
        app/qml/icons/torrent-categories/checking.png
        app/qml/icons/torrent-categories/downloading.png
        app/qml/icons/torrent-categories/inactive.png
        app/qml/icons/torrent-categories/moving.png
        app/qml/icons/torrent-categories/seeding.png
        app/qml/icons/torrent-categories/stopped.png
        tips.txt
)

file(GLOB STELLAR_FLAG_FILES RELATIVE "${CMAKE_SOURCE_DIR}"
    "app/qml/flags/*.svg")
qt_add_resources(Stellar "flags"
    PREFIX "/"
    FILES ${STELLAR_FLAG_FILES}
)


add_dependencies(Stellar StellarBuildTime)
target_include_directories(Stellar PRIVATE app/src ${CMAKE_BINARY_DIR})

target_link_libraries(Stellar PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickDialogs2
    Qt6::Widgets
    Qt6::Concurrent
)

if(ENABLE_LIBTORRENT AND LibtorrentRasterbar_FOUND)
    target_link_libraries(Stellar PRIVATE LibtorrentRasterbar::torrent-rasterbar)
    target_compile_definitions(Stellar PRIVATE STELLAR_HAS_LIBTORRENT=1)
endif()

if(ENABLE_MAXMINDDB AND TARGET maxminddb::maxminddb)
    target_link_libraries(Stellar PRIVATE maxminddb::maxminddb)
    target_compile_definitions(Stellar PRIVATE STELLAR_HAS_MAXMINDDB=1)
endif()


# ── Qt Quick Controls 2 configuration ────────────────────────────────────────
qt_add_resources(Stellar "conf"
    PREFIX "/"
    FILES qtquickcontrols2.conf
)

# ── Platform-specific ─────────────────────────────────────────────────────────
if(WIN32)
    set_target_properties(Stellar PROPERTIES
        WIN32_EXECUTABLE FALSE
    )
    target_compile_definitions(Stellar PRIVATE STELLAR_WINDOWS)
elseif(UNIX AND NOT APPLE)
    target_compile_definitions(Stellar PRIVATE STELLAR_LINUX)
endif()

# ── Deploy QtQuick.Dialogs QML plugin to build output ─────────────────────────
# windeployqt doesn't copy this automatically for in-tree debug builds
get_target_property(_qt_qml_dir Qt6::Core IMPORTED_LOCATION)
get_filename_component(_qt_root "${_qt_qml_dir}" DIRECTORY)   # bin/
get_filename_component(_qt_root "${_qt_root}" DIRECTORY)       # msvc2022_64/
set(_dialogs_src "${_qt_root}/qml/QtQuick/Dialogs")
set(_dialogs_dst "${CMAKE_BINARY_DIR}/qml/QtQuick/Dialogs")
if(EXISTS "${_dialogs_src}" AND NOT EXISTS "${_dialogs_dst}/qmldir")
    file(COPY "${_dialogs_src}/" DESTINATION "${_dialogs_dst}")
endif()

# ── Copy extensions to build output (dev convenience) ─────────────────────────
set(_ext_src "${CMAKE_SOURCE_DIR}/extensions")
set(_ext_dst "${CMAKE_BINARY_DIR}/extensions")
if(EXISTS "${_ext_src}")
    file(COPY "${_ext_src}/" DESTINATION "${_ext_dst}")
endif()

# Ensure the latest Firefox XPI is always copied on every build (not only on configure).
add_custom_command(TARGET Stellar POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:Stellar>/extensions/firefox"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_SOURCE_DIR}/extensions/firefox/stellar-firefox-0.1.6.xpi"
        "$<TARGET_FILE_DIR:Stellar>/extensions/firefox/stellar-firefox-0.1.6.xpi"
    COMMENT "Copying stellar-firefox-0.1.5.xpi to build output")

# ── Copy tips.txt to build output (dev convenience) ──────────────────────────
file(COPY "${CMAKE_SOURCE_DIR}/tips.txt"
    DESTINATION "${CMAKE_BINARY_DIR}"
)
file(COPY "${CMAKE_SOURCE_DIR}/app/data/dbip-city-lite-2026-04.mmdb"
    DESTINATION "${CMAKE_BINARY_DIR}/data"
)

# ── Install ────────────────────────────────────────────────────────────────────
install(TARGETS Stellar
    RUNTIME DESTINATION bin
    BUNDLE  DESTINATION .
)
install(FILES "${CMAKE_SOURCE_DIR}/tips.txt"
    DESTINATION "${CMAKE_INSTALL_BINDIR}"
)
install(FILES "${CMAKE_SOURCE_DIR}/app/data/dbip-city-lite-2026-04.mmdb"
    DESTINATION "${CMAKE_INSTALL_BINDIR}/data"
)
install(DIRECTORY "${CMAKE_SOURCE_DIR}/extensions/"
    DESTINATION "extensions"
)
