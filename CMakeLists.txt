cmake_minimum_required(VERSION 3.25)
project(Stellar VERSION 0.3.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

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

# ── Build timestamp (regenerated every configure) ─────────────────────────────
string(TIMESTAMP STELLAR_BUILD_TIME "%Y-%m-%d %H:%M UTC" UTC)
string(TIMESTAMP STELLAR_BUILD_DATE "%Y-%m-%d" UTC)
configure_file(app/src/AppVersion.h.in
               ${CMAKE_BINARY_DIR}/AppVersion.h
               @ONLY)

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
    app/src/SystemTrayIcon.cpp
    app/src/DownloadDatabase.cpp
    app/src/Queue.cpp
    app/src/QueueDatabase.cpp
    app/src/QueueModel.cpp
    app/src/FileDragDropHelper.cpp
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
    app/src/SystemTrayIcon.h
    app/src/DownloadDatabase.h
    app/src/Queue.h
    app/src/QueueDatabase.h
    app/src/QueueModel.h
    app/src/FileDragDropHelper.h
    app/src/FileIconImageProvider.h
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
        app/qml/icons/scheduler.ico
        app/qml/icons/help.ico
        app/qml/icons/arrow_down.ico
        app/qml/icons/arrow_up.ico
        app/qml/icons/rename.ico
        app/qml/icons/new_file.ico
        app/qml/icons/arrow_right.ico
        app/qml/icons/arrow_left.ico
        app/qml/icons/exit.ico
        app/qml/icons/add.ico
        app/qml/icons/Tools.ico
        app/qml/icons/wand.ico
        app/qml/icons/cancel.ico
        app/qml/icons/copy.ico
        app/qml/icons/paste.ico
        app/qml/icons/copy_file.ico
        app/qml/icons/move_file.ico
        app/qml/icons/x_square.ico
        app/qml/icons/milky-way.png
        app/qml/icons/milky-way.ico
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
        app/qml/icons/checkmark_download_complete.ico
        app/qml/icons/queues.png
        app/qml/icons/main_queue.png
        app/qml/icons/custom_queue.png
        app/qml/icons/synch_queue.png
        tips.txt
)


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

# ── Copy tips.txt to build output (dev convenience) ──────────────────────────
file(COPY "${CMAKE_SOURCE_DIR}/tips.txt"
    DESTINATION "${CMAKE_BINARY_DIR}"
)

# ── Install ────────────────────────────────────────────────────────────────────
install(TARGETS Stellar
    RUNTIME DESTINATION bin
    BUNDLE  DESTINATION .
)
install(FILES "${CMAKE_SOURCE_DIR}/tips.txt"
    DESTINATION "."
)
install(DIRECTORY "${CMAKE_SOURCE_DIR}/extensions/"
    DESTINATION "extensions"
)
