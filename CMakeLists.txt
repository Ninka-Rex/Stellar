cmake_minimum_required(VERSION 3.25)
project(Stellar VERSION 0.8.2 LANGUAGES C CXX)

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
    Sql
)
find_package(Qt6 OPTIONAL_COMPONENTS LinguistTools)

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
            if(TARGET torrent-rasterbar)
                # libtorrent unconditionally adds TORRENT_USE_ASSERTS for Debug
                # builds (generator expression in its CMakeLists). Its internal
                # assertions fire abort() when file_storage::num_pieces() is
                # called on a magnet with no metadata yet — a normal transient
                # state. Override with an explicit no-asserts definition so
                # debug builds stay usable.
                target_compile_definitions(torrent-rasterbar PUBLIC
                    $<$<CONFIG:Debug>:TORRENT_USE_ASSERTS=0>)
            endif()
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

# ── Windows version resource (configure time) ─────────────────────────────────
if(WIN32)
    configure_file(app/stellar.rc.in
                   ${CMAKE_BINARY_DIR}/stellar.rc
                   @ONLY)
endif()

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
    app/src/NetworkInfo.cpp
    app/src/BrowserCookieReader.cpp
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
    app/src/NetworkInfo.h
    app/src/BrowserCookieReader.h
)

# ── QML Resources ──────────────────────────────────────────────────────────────
if(WIN32)
    list(APPEND BACKEND_SOURCES ${CMAKE_BINARY_DIR}/stellar.rc)
endif()

qt_add_executable(Stellar ${BACKEND_SOURCES} ${BACKEND_HEADERS})

qt_add_qml_module(Stellar
    URI com.stellar.app
    VERSION 1.0
    QML_FILES
        app/qml/Main.qml
        app/qml/Toolbar.qml
        app/qml/Sidebar.qml
        app/qml/SidebarItemDragHandler.qml
        app/qml/SidebarSectionDragHandler.qml
        app/qml/DownloadTable.qml
        app/qml/DownloadTableHeader.qml
        app/qml/DownloadTableRow.qml
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
        app/qml/ToolbarDialog.qml
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
        app/qml/TorrentDuplicateDialog.qml
        app/qml/TorrentSpeedLimitDialog.qml
        app/qml/TorrentCreatorDialog.qml
        app/qml/DlgButton.qml
        app/qml/RssWindow.qml
        app/qml/RssDownloadRulesDialog.qml
        app/qml/TorrentSearchWindow.qml
        app/qml/TorrentSearchPluginsDialog.qml
        app/qml/TorrentSearchInstallDialog.qml
        app/qml/StatisticsDialog.qml
    RESOURCES
        app/qml/icons/add.svg
        app/qml/icons/resume.svg
        app/qml/icons/delete.svg
        app/qml/icons/wastebasket.svg
        app/qml/icons/delete_done.svg
        app/qml/icons/gear.svg
        app/qml/icons/add_url.svg
        app/qml/icons/start_queue.svg
        app/qml/icons/stop_queue.svg
        app/qml/icons/stop_all.svg
        app/qml/icons/tools.svg
        app/qml/icons/toolbar.svg
        app/qml/icons/pause.svg
        app/qml/icons/properties.svg
        app/qml/icons/scheduler.svg
        app/qml/icons/update.svg
        app/qml/icons/bar_chart.svg
        app/qml/icons/snail.svg
        app/qml/icons/torrent_file.svg
        app/qml/icons/export_torrent.svg
        app/qml/icons/satellite_antenna.svg
        app/qml/icons/columns.svg
        app/qml/icons/hide_categories.svg
        app/qml/icons/arrow_down.svg
        app/qml/icons/rename.svg
        app/qml/icons/new_file.svg
        app/qml/icons/exit.svg
        app/qml/icons/grabber.svg
        app/qml/icons/wand.svg
        app/qml/icons/magnifying_glass.svg
        app/qml/icons/rss.svg
        app/qml/icons/copy.svg
        app/qml/icons/milky-way.png
        app/qml/icons/milky-way-white.png
        app/qml/icons/milky-way-black.png
        app/qml/icons/milky-way.ico
        app/qml/icons/milky-way.gif
        app/qml/icons/magnet.svg
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
        app/qml/icons/folder.svg
        app/qml/icons/categories/all_downloads.svg
        app/qml/icons/categories/compressed.svg
        app/qml/icons/categories/documents.svg
        app/qml/icons/categories/note.svg
        app/qml/icons/categories/programs.svg
        app/qml/icons/categories/video.svg
        app/qml/icons/checkmark.svg
        app/qml/icons/queues.svg
        app/qml/icons/main_queue.svg
        app/qml/icons/custom_queue.svg
        app/qml/icons/synch_queue.svg
        app/qml/icons/globe.svg
        app/qml/icons/information.svg
        app/qml/icons/link.svg
        app/qml/icons/delete.svg
        app/qml/icons/file_no_longer_available.svg
        app/qml/icons/world-map.svg
        app/qml/icons/page.svg
        app/qml/icons/cloud_copylink.svg
        app/qml/icons/folder_view.svg
        app/qml/icons/about.svg
        app/qml/icons/torrent-categories/all_torrents.svg
        app/qml/icons/torrent-categories/active.svg
        app/qml/icons/torrent-categories/checking.svg
        app/qml/icons/torrent-categories/downloading.svg
        app/qml/icons/torrent-categories/inactive.svg
        app/qml/icons/torrent-categories/moving.svg
        app/qml/icons/torrent-categories/seeding.svg
        app/qml/icons/torrent-categories/stopped.svg
        tips.txt
)

file(GLOB STELLAR_FLAG_FILES RELATIVE "${CMAKE_SOURCE_DIR}"
    "app/qml/flags/*.svg")
qt_add_resources(Stellar "flags"
    PREFIX "/"
    FILES ${STELLAR_FLAG_FILES}
)


# ── Translations ───────────────────────────────────────────────────────────────
# Run lupdate manually to regenerate .ts files after adding new qsTr() strings:
#   lupdate app/src app/qml -ts translations/stellar_fr.ts
# Run lrelease (or just build) to compile .ts → .qm before shipping.
if(Qt6LinguistTools_FOUND)
    qt_add_translations(Stellar
        TS_FILES
            translations/stellar_am.ts
            translations/stellar_ar.ts
            translations/stellar_az.ts
            translations/stellar_be.ts
            translations/stellar_bg.ts
            translations/stellar_bn.ts
            translations/stellar_bs.ts
            translations/stellar_ca.ts
            translations/stellar_cs.ts
            translations/stellar_da.ts
            translations/stellar_de.ts
            translations/stellar_el.ts
            translations/stellar_en.ts
            translations/stellar_es.ts
            translations/stellar_et.ts
            translations/stellar_fa.ts
            translations/stellar_fi.ts
            translations/stellar_fil.ts
            translations/stellar_fr.ts
            translations/stellar_ga.ts
            translations/stellar_gl.ts
            translations/stellar_gu.ts
            translations/stellar_ha.ts
            translations/stellar_he.ts
            translations/stellar_hi.ts
            translations/stellar_hr.ts
            translations/stellar_hu.ts
            translations/stellar_hy.ts
            translations/stellar_id.ts
            translations/stellar_ig.ts
            translations/stellar_it.ts
            translations/stellar_ja.ts
            translations/stellar_jv.ts
            translations/stellar_ka.ts
            translations/stellar_km.ts
            translations/stellar_kn.ts
            translations/stellar_ko.ts
            translations/stellar_lo.ts
            translations/stellar_lv.ts
            translations/stellar_lt.ts
            translations/stellar_mk.ts
            translations/stellar_ml.ts
            translations/stellar_mn.ts
            translations/stellar_mr.ts
            translations/stellar_ms.ts
            translations/stellar_my.ts
            translations/stellar_nb.ts
            translations/stellar_ne.ts
            translations/stellar_nl.ts
            translations/stellar_nl_BE.ts
            translations/stellar_pa.ts
            translations/stellar_pl.ts
            translations/stellar_ps.ts
            translations/stellar_pt.ts
            translations/stellar_pt_BR.ts
            translations/stellar_ro.ts
            translations/stellar_ru.ts
            translations/stellar_si.ts
            translations/stellar_sk.ts
            translations/stellar_sl.ts
            translations/stellar_sq.ts
            translations/stellar_sr_Cyrl.ts
            translations/stellar_sr_Latn.ts
            translations/stellar_sv.ts
            translations/stellar_sw.ts
            translations/stellar_ta.ts
            translations/stellar_te.ts
            translations/stellar_th.ts
            translations/stellar_tr.ts
            translations/stellar_ug.ts
            translations/stellar_uk.ts
            translations/stellar_ur.ts
            translations/stellar_uz.ts
            translations/stellar_vi.ts
            translations/stellar_cy.ts
            translations/stellar_yo.ts
            translations/stellar_zh_CN.ts
            translations/stellar_zh_TW.ts
        RESOURCE_PREFIX /i18n
    )
endif()

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
    Qt6::Sql
)

if(WIN32)
    target_link_libraries(Stellar PRIVATE wlanapi)
endif()

if(UNIX AND NOT APPLE)
    # dlopen/dlsym for dynamic libcrypto loading (Chromium cookie decryption)
    target_link_libraries(Stellar PRIVATE dl)
endif()

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
        WIN32_EXECUTABLE TRUE
    )
    target_compile_definitions(Stellar PRIVATE STELLAR_WINDOWS)
elseif(UNIX AND NOT APPLE)
    target_compile_definitions(Stellar PRIVATE STELLAR_LINUX)
    # Feed CPack / packaging tools with human-readable metadata.
    set(CPACK_PACKAGE_NAME        "stellar-download-manager")
    set(CPACK_PACKAGE_VENDOR      "Ninka_")
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Fast, segmented, IDM-style download manager")
    set(CPACK_PACKAGE_VERSION     "${PROJECT_VERSION}")
    set(CPACK_PACKAGE_CONTACT     "https://github.com/Ninka-Rex/Stellar")
    set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_SOURCE_DIR}/LICENSE")
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

# ── Copy tips.txt to build output (dev convenience) ──────────────────────────
file(COPY "${CMAKE_SOURCE_DIR}/tips.txt"
    DESTINATION "${CMAKE_BINARY_DIR}"
)
file(GLOB geo_db_files "${CMAKE_SOURCE_DIR}/app/data/dbip-city-lite-*.mmdb")
if(geo_db_files)
    list(GET geo_db_files 0 geo_db_file)
    file(COPY "${geo_db_file}" DESTINATION "${CMAKE_BINARY_DIR}/data")
    message(STATUS "Geo IP database: ${geo_db_file}")
else()
    message(STATUS "Geo IP database not found in app/data/ — build will proceed without it")
endif()

# ── Install ────────────────────────────────────────────────────────────────────
install(TARGETS Stellar
    RUNTIME DESTINATION bin
    BUNDLE  DESTINATION .
)
install(FILES "${CMAKE_SOURCE_DIR}/tips.txt"
    DESTINATION "${CMAKE_INSTALL_BINDIR}"
)
file(GLOB geo_db_install_files "${CMAKE_SOURCE_DIR}/app/data/dbip-city-lite-*.mmdb")
if(geo_db_install_files)
    list(GET geo_db_install_files 0 geo_db_install_file)
    install(FILES "${geo_db_install_file}"
        DESTINATION "${CMAKE_INSTALL_BINDIR}/data"
    )
endif()
