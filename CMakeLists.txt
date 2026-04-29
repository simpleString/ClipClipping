cmake_minimum_required(VERSION 3.21)
project(telegramGifterQt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Multimedia Concurrent Widgets)

qt_standard_project_setup()

qt_add_executable(telegramGifterQt
    src/main.cpp
    src/AppController.h
    src/AppController.cpp
)

qt_add_resources(telegramGifterQt "app_config"
    PREFIX "/"
    FILES
        qtquickcontrols2.conf
)

qt_add_qml_module(telegramGifterQt
    URI TelegramGifter
    VERSION 1.0
    QML_FILES
        src/ui/Main.qml
)

target_link_libraries(telegramGifterQt
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Multimedia
        Qt6::Concurrent
        Qt6::Widgets
)
