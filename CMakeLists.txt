cmake_minimum_required(VERSION 3.21)
project(ClipClipping LANGUAGES CXX)

if(NOT DEFINED CLIP_VERSION)
    set(CLIP_VERSION "0.0.0-dev")
endif()

string(REGEX MATCH "^([0-9]+)\\.([0-9]+)\\.([0-9]+)" _vmatch "${CLIP_VERSION}")
set(PROJECT_VERSION "${CLIP_VERSION}")
set(PROJECT_VERSION_MAJOR "${CMAKE_MATCH_1}")
set(PROJECT_VERSION_MINOR "${CMAKE_MATCH_2}")
set(PROJECT_VERSION_PATCH "${CMAKE_MATCH_3}")

include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Multimedia Concurrent Widgets)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

set(CPACK_PACKAGE_NAME "ClipClipping")
set(CPACK_PACKAGE_VENDOR "ClipClipping")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Video to GIF/WEBM clip creator")
set(CPACK_PACKAGE_ICON "${CMAKE_SOURCE_DIR}/assets/ClipClippingIcon.ico")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")

qt_add_executable(ClipClipping
    src/main.cpp
    src/AppController.h
    src/AppController.cpp
)

if(WIN32)
    configure_file(
        "${CMAKE_SOURCE_DIR}/assets/app.rc.in"
        "${CMAKE_BINARY_DIR}/app.rc"
        @ONLY
    )
    target_sources(ClipClipping PRIVATE
        "${CMAKE_BINARY_DIR}/app.rc"
    )
endif()

qt_add_resources(ClipClipping "app_assets"
    PREFIX "/"
    FILES
        assets/ClipClippingIcon.png
)

qt_add_qml_module(ClipClipping
    URI ClipClipping
    VERSION 1.0
    QML_FILES
        src/ui/Main.qml
)

set_target_properties(ClipClipping PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

install(TARGETS ClipClipping
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

qt_generate_deploy_app_script(
    TARGET ClipClipping
    OUTPUT_SCRIPT deploy_script
    NO_UNSUPPORTED_PLATFORM_ERROR
)
install(SCRIPT ${deploy_script})

target_link_libraries(ClipClipping
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Multimedia
        Qt6::Concurrent
        Qt6::Widgets
)

if(WIN32)
    set(CPACK_GENERATOR "ZIP;NSIS")
    set(CPACK_NSIS_DISPLAY_NAME "ClipClipping")
    set(CPACK_NSIS_PACKAGE_NAME "ClipClipping")
    set(CPACK_NSIS_INSTALL_ROOT "$LOCALAPPDATA")
    set(CPACK_NSIS_MUI_ICON "${CMAKE_SOURCE_DIR}/assets/ClipClippingIcon.ico")
    set(CPACK_NSIS_MUI_UNIICON "${CMAKE_SOURCE_DIR}/assets/ClipClippingIcon.ico")
    set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
    set(CPACK_NSIS_CREATE_ICONS_EXTRA
        "CreateShortCut '$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\ClipClipping.lnk' '$INSTDIR\\\\bin\\\\ClipClipping.exe'"
    )
    set(CPACK_NSIS_DELETE_ICONS_EXTRA
        "Delete '$SMPROGRAMS\\\\$START_MENU\\\\ClipClipping.lnk'"
    )
    set(CPACK_NSIS_INSTALLED_ICON_NAME "bin\\\\ClipClipping.exe")
    set(CPACK_NSIS_URL_INFO_ABOUT "https://github.com/simplestring/ClipClipping")
else()
    set(CPACK_GENERATOR "ZIP")
endif()

include(CPack)
