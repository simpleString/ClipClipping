#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QImage>

class QMediaPlayer;
class QVideoSink;
class QVideoFrame;

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
    Q_PROPERTY(bool stickerWebmMode READ stickerWebmMode WRITE setStickerWebmMode NOTIFY settingsChanged)
    Q_PROPERTY(bool includeSubtitles READ includeSubtitles WRITE setIncludeSubtitles NOTIFY settingsChanged)
    Q_PROPERTY(int subtitleStreamIndex READ subtitleStreamIndex WRITE setSubtitleStreamIndex NOTIFY settingsChanged)
    Q_PROPERTY(bool converting READ converting NOTIFY conversionStateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY conversionStateChanged)
    Q_PROPERTY(QStringList thumbnailUrls READ thumbnailUrls NOTIFY thumbnailsChanged)
    Q_PROPERTY(int thumbnailsVersion READ thumbnailsVersion NOTIFY thumbnailsChanged)
    Q_PROPERTY(int thumbnailsGenerated READ thumbnailsGenerated NOTIFY thumbnailsChanged)
    Q_PROPERTY(double thumbWindowFrom READ thumbWindowFrom NOTIFY thumbnailsChanged)
    Q_PROPERTY(double thumbWindowTo READ thumbWindowTo NOTIFY thumbnailsChanged)
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
    bool stickerWebmMode() const;
    bool includeSubtitles() const;
    int subtitleStreamIndex() const;
    bool converting() const;
    int progress() const;
    QStringList thumbnailUrls() const;
    int thumbnailsVersion() const;
    int thumbnailsGenerated() const;
    double thumbWindowFrom() const;
    double thumbWindowTo() const;
    QString errorMessage() const;
    QString successMessage() const;
    double estimatedSizeMb() const;

    Q_INVOKABLE void openVideo(const QString &filePath);
    Q_INVOKABLE void openVideoDialog();
    Q_INVOKABLE void openSaveGifDialog();
    Q_INVOKABLE void startConversion(const QString &outputPath);
    Q_INVOKABLE void cancelConversion();
    Q_INVOKABLE void clearVideo();
    Q_INVOKABLE void ensureThumbnailsForCount(int count);
    Q_INVOKABLE void ensureThumbnailsForWindow(int count, double fromSec, double toSec);
    bool hasVideo() const;

public slots:
    void setCurrentTime(double value);
    void setStartTime(double value);
    void setEndTime(double value);
    void setTargetWidth(int value);
    void setTargetFps(int value);
    void setStickerWebmMode(bool value);
    void setIncludeSubtitles(bool value);
    void setSubtitleStreamIndex(int value);

signals:
    void videoPathChanged();
    void videoUrlChanged();
    void videoMetaChanged();
    void currentTimeChanged();
    void trimChanged();
    void settingsChanged();
    void conversionStateChanged();
    void thumbnailsChanged();
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
        QList<int> subtitleStreamIndexes;
    };

    struct AttemptConfig {
        double scale;
        int fpsMod;
    };

    static int parseFps(const QString &rate);
    static double parseFfmpegTimeToSeconds(const QString &line);
    static QList<AttemptConfig> buildConfigs(double clipDuration, int width, int fps, qint64 maxFileSize);
    static QList<int> buildWebmCrfConfigs(double clipDuration);
    QStringList subtitleFilterPrefixes(double startTime, QString *error) const;
    static QString localFileUrl(const QString &path);

    VideoInfo probeVideo(const QString &path, QString *error) const;
    bool runAttempt(const QString &inputPath,
                    const QString &outputPath,
                    double startTime,
                    double clipDuration,
                    int fps,
                    int width);
    bool runWebmStickerAttempt(const QString &inputPath,
                               const QString &outputPath,
                               double startTime,
                               double clipDuration,
                               int width,
                               int fps,
                               int crf);
    void startThumbnailGeneration(int count);
    void continueThumbnailGeneration();
    void onThumbnailStepTimeout();
    void finishThumbnailGeneration();

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
    bool m_stickerWebmMode = false;
    bool m_includeSubtitles = false;
    int m_subtitleStreamIndex = -1;

    bool m_converting = false;
    int m_progress = 0;
    QStringList m_thumbnailUrls;
    int m_thumbnailsVersion = 0;
    int m_thumbnailsGenerated = 0;
    QString m_errorMessage;
    QString m_successMessage;

    QProcess *m_activeFfmpeg = nullptr;
    bool m_cancelRequested = false;
    int m_thumbnailCount = 0;
    int m_thumbnailPoolCount = 0;
    int m_pendingThumbnailCount = 0;
    bool m_thumbnailGenerating = false;
    QStringList m_thumbnailPoolUrls;
    double m_thumbWindowFrom = 0.0;
    double m_thumbWindowTo = 0.0;

    QMediaPlayer *m_thumbPlayer = nullptr;
    QVideoSink *m_thumbSink = nullptr;
    QTimer m_thumbStepTimer;
    int m_thumbTargetCount = 0;
    int m_thumbCurrentIndex = 0;
    double m_thumbStepSec = 0.0;
    double m_thumbRequestedSec = 0.0;
    bool m_thumbFrameReady = false;
    int m_thumbRetryCount = 0;
    QImage m_lastThumbImage;
    QProcess *m_thumbFfmpegProcess = nullptr;
    QString m_thumbOutputDir;
    QString m_thumbCacheKey;
    int m_thumbExpectedCount = 0;
    int m_thumbRequestedSeq = 0;
    int m_thumbRunningSeq = 0;
};
