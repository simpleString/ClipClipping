#include <QApplication>
#include <QAbstractNativeEventFilter>
#include <QByteArray>
#include <QMetaObject>
#include <QEvent>
#include <QKeyEvent>
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
#ifdef Q_OS_WIN
        m_timer.setInterval(30);
        connect(&m_timer, &QTimer::timeout, this, &KeyStateTracker::poll);
        m_timer.start();
        poll();
#endif
    }

    bool altPressed() const { return m_altPressed; }
    Q_INVOKABLE bool altPressedNow() const {
#ifdef Q_OS_WIN
        return (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
#else
        return m_altPressed;
#endif
    }

    bool eventFilter(QObject *watched, QEvent *event) override {
        Q_UNUSED(watched)
        if (!event) {
            return false;
        }

        if (event->type() == QEvent::KeyPress) {
            const auto *keyEvent = static_cast<QKeyEvent *>(event);
            if (keyEvent->key() == Qt::Key_Alt) {
                setAltPressed(true);
#ifndef Q_OS_WIN
            } else if (!keyEvent->isAutoRepeat() && isMarkInKey(*keyEvent)) {
                emit markInPressed();
            } else if (!keyEvent->isAutoRepeat() && isMarkOutKey(*keyEvent)) {
                emit markOutPressed();
#endif
            }
        } else if (event->type() == QEvent::KeyRelease) {
            const auto *keyEvent = static_cast<QKeyEvent *>(event);
            if (keyEvent->key() == Qt::Key_Alt) {
                setAltPressed(false);
            }
        } else if (event->type() == QEvent::ApplicationDeactivate) {
            setAltPressed(false);
        }

        return false;
    }

signals:
    void altPressedChanged();
    void altWheel(int delta);
    void markInPressed();
    void markOutPressed();

private:
    static bool isMarkInKey(const QKeyEvent &event) {
        if (event.key() == Qt::Key_I) {
            return true;
        }
#ifdef Q_OS_WIN
        return event.nativeVirtualKey() == 0x49;
#elif defined(Q_OS_LINUX)
        const quint32 sc = event.nativeScanCode();
        return sc == 23 || sc == 31;
#else
        return false;
#endif
    }

    static bool isMarkOutKey(const QKeyEvent &event) {
        if (event.key() == Qt::Key_O) {
            return true;
        }
#ifdef Q_OS_WIN
        return event.nativeVirtualKey() == 0x4F;
#elif defined(Q_OS_LINUX)
        const quint32 sc = event.nativeScanCode();
        return sc == 24 || sc == 32;
#else
        return false;
#endif
    }

    void setAltPressed(bool value) {
        if (value == m_altPressed) {
            return;
        }
        m_altPressed = value;
        emit altPressedChanged();
    }

    void poll() {
#ifdef Q_OS_WIN
        const bool value = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
        setAltPressed(value);
#endif
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
        if (!msg) {
            return false;
        }

        if (msg->message == WM_KEYDOWN || msg->message == WM_SYSKEYDOWN) {
            const WPARAM vk = msg->wParam;
            if (vk == 0x49) {
                QMetaObject::invokeMethod(
                    m_tracker,
                    [this]() { emit m_tracker->markInPressed(); },
                    Qt::QueuedConnection
                );
            } else if (vk == 0x4F) {
                QMetaObject::invokeMethod(
                    m_tracker,
                    [this]() { emit m_tracker->markOutPressed(); },
                    Qt::QueuedConnection
                );
            }
            return false;
        }

        if (msg->message != WM_MOUSEWHEEL) {
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
    app.installEventFilter(&keyState);
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
    engine.loadFromModule("ClipClipping", "Main");

    return app.exec();
}

#include "main.moc"
