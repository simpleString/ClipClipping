#pragma once

#include <QObject>
#include <QProcess>

class AppController : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hasVideo READ hasVideo NOTIFY videoPathChanged)
    Q_PROPERTY(QString videoPath READ videoPath NOTIFY videoPathChanged)
    Q_PROPERTY(QString videoUrl READ videoUrl NOTIFY videoUrlChanged)
    Q_PROPERTY(double duration READ duration NOTIFY videoMetaChanged)
    Q_PROPERTY(double currentTime READ currentTime WRITE setCurrentTime NOTIFY currentTimeChanged)
    Q_PROPERTY(double startTime READ startTime WRITE setStartTime NOTIFY trimChanged)
    Q_PROPERTY(double endTime READ endTime WRITE setEndTime NOTIFY trimChanged)
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY videoMetaChanged)
    Q_PROPERTY(int videoFps READ videoFps NOTIFY videoMetaChanged)
    Q_PROPERTY(int targetWidth READ targetWidth WRITE setTargetWidth NOTIFY settingsChanged)
    Q_PROPERTY(int targetFps READ targetFps WRITE setTargetFps NOTIFY settingsChanged)
    Q_PROPERTY(bool converting READ converting NOTIFY conversionStateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY conversionStateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QString successMessage READ successMessage NOTIFY successMessageChanged)
    Q_PROPERTY(double estimatedSizeMb READ estimatedSizeMb NOTIFY settingsChanged)

public:
    explicit AppController(QObject *parent = nullptr);

    QString videoPath() const;
    QString videoUrl() const;
    double duration() const;
    double currentTime() const;
    double startTime() const;
    double endTime() const;
    int videoWidth() const;
    int videoFps() const;
    int targetWidth() const;
    int targetFps() const;
    bool converting() const;
    int progress() const;
    QString errorMessage() const;
    QString successMessage() const;
    double estimatedSizeMb() const;

    Q_INVOKABLE void openVideo(const QString &filePath);
    Q_INVOKABLE void openVideoDialog();
    Q_INVOKABLE void openSaveGifDialog();
    Q_INVOKABLE void startConversion(const QString &outputPath);
    Q_INVOKABLE void cancelConversion();
    bool hasVideo() const;

public slots:
    void setCurrentTime(double value);
    void setStartTime(double value);
    void setEndTime(double value);
    void setTargetWidth(int value);
    void setTargetFps(int value);

signals:
    void videoPathChanged();
    void videoUrlChanged();
    void videoMetaChanged();
    void currentTimeChanged();
    void trimChanged();
    void settingsChanged();
    void conversionStateChanged();
    void errorMessageChanged();
    void successMessageChanged();

private:
    struct VideoInfo {
        double duration = 0.0;
        int width = 0;
        int height = 0;
        int fps = 30;
        QString codec;
        qint64 size = 0;
    };

    struct AttemptConfig {
        double scale;
        int fpsMod;
    };

    static int parseFps(const QString &rate);
    static double parseFfmpegTimeToSeconds(const QString &line);
    static QList<AttemptConfig> buildConfigs(double clipDuration, int width, int fps, qint64 maxFileSize);
    static QString localFileUrl(const QString &path);

    VideoInfo probeVideo(const QString &path, QString *error) const;
    bool runAttempt(const QString &inputPath,
                    const QString &outputPath,
                    double startTime,
                    double clipDuration,
                    int fps,
                    int width);

    void setError(const QString &message);
    void clearMessages();
    void setConverting(bool value);
    void setProgress(int value);

    QString m_videoPath;
    QString m_videoUrl;
    VideoInfo m_videoInfo;

    double m_currentTime = 0.0;
    double m_startTime = 0.0;
    double m_endTime = 0.0;

    int m_targetWidth = 480;
    int m_targetFps = 15;

    bool m_converting = false;
    int m_progress = 0;
    QString m_errorMessage;
    QString m_successMessage;

    QProcess *m_activeFfmpeg = nullptr;
    bool m_cancelRequested = false;
};
