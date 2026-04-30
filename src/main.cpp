#include <QApplication>
#include <QAbstractNativeEventFilter>
#include <QByteArray>
#include <QMetaObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>
#include <QtGlobal>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

#include "AppController.h"

class KeyStateTracker : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool altPressed READ altPressed NOTIFY altPressedChanged)

public:
    explicit KeyStateTracker(QObject *parent = nullptr) : QObject(parent) {
        m_timer.setInterval(30);
        connect(&m_timer, &QTimer::timeout, this, &KeyStateTracker::poll);
        m_timer.start();
        poll();
    }

    bool altPressed() const { return m_altPressed; }
    Q_INVOKABLE bool altPressedNow() const {
#ifdef Q_OS_WIN
        return (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
#else
        return false;
#endif
    }

signals:
    void altPressedChanged();
    void altWheel(int delta);

private:
    void poll() {
        bool value = false;
#ifdef Q_OS_WIN
        value = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
#endif
        if (value == m_altPressed) {
            return;
        }
        m_altPressed = value;
        emit altPressedChanged();
    }

    bool m_altPressed = false;
    QTimer m_timer;
};

#ifdef Q_OS_WIN
class AltWheelNativeFilter : public QAbstractNativeEventFilter {
public:
    explicit AltWheelNativeFilter(KeyStateTracker *tracker) : m_tracker(tracker) {}

    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override {
        Q_UNUSED(result)
        if (!m_tracker || eventType != "windows_generic_MSG") {
            return false;
        }

        const MSG *msg = static_cast<MSG *>(message);
        if (!msg || msg->message != WM_MOUSEWHEEL) {
            return false;
        }

        if ((GetAsyncKeyState(VK_MENU) & 0x8000) == 0) {
            return false;
        }

        const int delta = GET_WHEEL_DELTA_WPARAM(msg->wParam);
        QMetaObject::invokeMethod(
            m_tracker,
            [this, delta]() { emit m_tracker->altWheel(delta); },
            Qt::QueuedConnection
        );
        return false;
    }

private:
    KeyStateTracker *m_tracker = nullptr;
};
#endif

int main(int argc, char *argv[]) {
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    qputenv("QT_QUICK_CONTROLS_FALLBACK_STYLE", "Basic");
    qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "");
    QQuickStyle::setStyle("Basic");
    QApplication app(argc, argv);
    QQmlApplicationEngine engine;

    AppController controller;
    KeyStateTracker keyState;
#ifdef Q_OS_WIN
    AltWheelNativeFilter altWheelFilter(&keyState);
    app.installNativeEventFilter(&altWheelFilter);
#endif
    engine.rootContext()->setContextProperty("appController", &controller);
    engine.rootContext()->setContextProperty("keyState", &keyState);

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

#include "main.moc"
