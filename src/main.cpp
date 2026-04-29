#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QtGlobal>

#include "AppController.h"

int main(int argc, char *argv[]) {
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    qputenv("QT_QUICK_CONTROLS_FALLBACK_STYLE", "Basic");
    qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "");
    QQuickStyle::setStyle("Basic");
    QApplication app(argc, argv);
    QQmlApplicationEngine engine;

    AppController controller;
    engine.rootContext()->setContextProperty("appController", &controller);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection
    );
    engine.loadFromModule("TelegramGifter", "Main");

    return app.exec();
}
