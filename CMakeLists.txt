cmake_minimum_required(VERSION 3.21)
project(ClipClipping LANGUAGES CXX)

include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Multimedia Concurrent Widgets)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

qt_add_executable(ClipClipping
    src/main.cpp
    src/AppController.h
    src/AppController.cpp
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
