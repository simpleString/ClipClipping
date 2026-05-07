#include "AppController.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileDialog>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QMediaPlayer>
#include <QVideoSink>
#include <QVideoFrame>
#include <QImage>
#include <QtConcurrent>

#include <algorithm>
#include <cmath>

namespace {
constexpr qint64 kMaxGifSize = 10 * 1024 * 1024;
constexpr qint64 kMaxStickerWebmSize = 256 * 1024;
constexpr int kFixedThumbCount = 12;
const QString kLastImportPathKey = QStringLiteral("ui/lastImportPath");
const QString kLastExportPathKey = QStringLiteral("ui/lastExportPath");

QString bundledToolPath(const QString &toolName) {
#ifdef Q_OS_WIN
    const QString fileName = toolName + ".exe";
#else
    const QString fileName = toolName;
#endif
    const QString fullPath = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("tools/%1").arg(fileName));
    const QFileInfo fi(fullPath);
    if (fi.exists() && fi.isFile() && fi.isExecutable()) {
        return fullPath;
    }
    return toolName;
}

QStringList generateThumbnailsWithFfmpegFallback(const QString &videoPath, double duration, int count, double fromSec, double toSec) {
    QStringList urls;
    const QString tmpRoot = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (tmpRoot.isEmpty() || duration <= 0.0 || count <= 0) {
        return urls;
    }

    const QFileInfo info(videoPath);
    const double clampedFrom = std::max(0.0, std::min(fromSec, duration));
    const double clampedTo = std::max(clampedFrom + 0.05, std::min(toSec, duration));
    const double span = std::max(0.05, clampedTo - clampedFrom);

    const QByteArray key = videoPath.toUtf8()
        + QByteArray::number(info.size())
        + QByteArray::number(qint64(info.lastModified().toMSecsSinceEpoch()))
        + QByteArray::number(qint64(clampedFrom * 1000.0))
        + QByteArray::number(qint64(clampedTo * 1000.0))
        + QByteArrayLiteral("thumb_ffmpeg_parallel_v2");
    const QString hash = QString::fromLatin1(QCryptographicHash::hash(key, QCryptographicHash::Md5).toHex());
    const QString dirPath = QDir(tmpRoot).filePath(QStringLiteral("clipclipping_thumbs/%1/fallback_%2").arg(hash).arg(count));
    QDir dir(dirPath);
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    struct Job {
        int idx;
        QString outPath;
        QProcess *proc;
    };

    QList<Job> jobs;
    jobs.reserve(count);

    for (int i = 0; i < count; ++i) {
        const QString outPath = dir.filePath(QStringLiteral("thumb_%1.png").arg(i, 3, 10, QChar('0')));
        if (!QFileInfo::exists(outPath)) {
            const double pos = clampedFrom + span * (double(i) + 0.5) / double(count);
            auto *proc = new QProcess();
            QStringList args{
                "-y",
                "-ss", QString::number(pos, 'f', 4),
                "-i", videoPath,
                "-frames:v", "1",
                "-vf", "scale=96:-2",
                "-q:v", "8",
                outPath
            };
            proc->start(bundledToolPath(QStringLiteral("ffmpeg")), args);
            jobs.push_back({i, outPath, proc});
        }
    }

    for (const Job &job : jobs) {
        if (job.proc->state() == QProcess::Starting) {
            job.proc->waitForStarted(1500);
        }
    }
    for (const Job &job : jobs) {
        if (!job.proc->waitForFinished(7000)) {
            job.proc->kill();
            job.proc->waitForFinished(1000);
        }
        delete job.proc;
    }

    for (int i = 0; i < count; ++i) {
        const QString outPath = dir.filePath(QStringLiteral("thumb_%1.png").arg(i, 3, 10, QChar('0')));
        if (QFileInfo::exists(outPath)) {
            urls.push_back(QUrl::fromLocalFile(outPath).toString());
        } else if (!urls.isEmpty()) {
            urls.push_back(urls.back());
        } else {
            urls.push_back(QString());
        }
    }
    return urls;
}
}

AppController::AppController(QObject *parent) : QObject(parent) {
    m_thumbStepTimer.setSingleShot(true);
    connect(&m_thumbStepTimer, &QTimer::timeout, this, &AppController::onThumbnailStepTimeout);
}

QString AppController::videoPath() const { return m_videoPath; }
QString AppController::videoUrl() const { return m_videoUrl; }
double AppController::duration() const { return m_videoInfo.duration; }
double AppController::currentTime() const { return m_currentTime; }
double AppController::startTime() const { return m_startTime; }
double AppController::endTime() const { return m_endTime; }
int AppController::videoWidth() const { return m_videoInfo.width; }
int AppController::videoFps() const { return m_videoInfo.fps; }
int AppController::targetWidth() const { return m_targetWidth; }
int AppController::targetFps() const { return m_targetFps; }
bool AppController::stickerWebmMode() const { return m_stickerWebmMode; }
bool AppController::includeSubtitles() const { return m_includeSubtitles; }
int AppController::subtitleStreamIndex() const { return m_subtitleStreamIndex; }
bool AppController::converting() const { return m_converting; }
int AppController::progress() const { return m_progress; }
QStringList AppController::thumbnailUrls() const { return m_thumbnailUrls; }
int AppController::thumbnailsVersion() const { return m_thumbnailsVersion; }
int AppController::thumbnailsGenerated() const { return m_thumbnailsGenerated; }
double AppController::thumbWindowFrom() const { return m_thumbWindowFrom; }
double AppController::thumbWindowTo() const { return m_thumbWindowTo; }
QString AppController::errorMessage() const { return m_errorMessage; }
QString AppController::successMessage() const { return m_successMessage; }
double AppController::estimatedSizeMb() const {
    const double clipDuration = std::max(0.0, m_endTime - m_startTime);
    if (m_stickerWebmMode) {
        const double estKb = (double(m_targetFps) / 30.0) * clipDuration * 120.0;
        return estKb / 1024.0;
    }
    const double est = (double(m_targetWidth) / 480.0) * (double(m_targetFps) / 15.0) * clipDuration * 0.8;
    return est;
}

bool AppController::hasVideo() const {
    return !m_videoPath.isEmpty();
}

void AppController::openVideoDialog() {
    const QString filter = "Video files (*.mp4 *.avi *.mkv *.mov *.webm *.flv *.wmv *.ts *.m4v);;All files (*)";
    QSettings settings;
    QString startPath = settings.value(kLastImportPathKey).toString();
    if (startPath.isEmpty()) {
        startPath = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    }
    if (startPath.isEmpty()) {
        startPath = QDir::homePath();
    }
    QFileDialog dialog(nullptr, "Select Video", startPath);
    dialog.setFileMode(QFileDialog::ExistingFile);
    dialog.setNameFilter(filter);
    dialog.setOption(QFileDialog::DontUseNativeDialog, false);
    if (!dialog.exec()) {
        return;
    }
    const QStringList files = dialog.selectedFiles();
    const QString filePath = files.isEmpty() ? QString() : files.first();
    if (filePath.isEmpty()) {
        return;
    }
    settings.setValue(kLastImportPathKey, QFileInfo(filePath).absoluteFilePath());
    openVideo(filePath);
}

void AppController::openSaveGifDialog() {
    clearMessages();
    const bool webm = m_stickerWebmMode;
    const double clipDuration = m_endTime - m_startTime;
    if (webm && clipDuration > 3.0) {
        setError("Sticker WEBM duration must be 3 seconds or less.");
        return;
    }
    QSettings settings;
    const QString filter = webm ? "WEBM files (*.webm)" : "GIF files (*.gif)";
    const QString lastExportPath = settings.value(kLastExportPathKey).toString();
    QString suggestedPath;
    if (!lastExportPath.isEmpty()) {
        QFileInfo lastInfo(lastExportPath);
        suggestedPath = lastInfo.absolutePath();
    }
    if (suggestedPath.isEmpty()) {
        suggestedPath = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    }
    if (suggestedPath.isEmpty()) {
        suggestedPath = QDir::homePath();
    }
    QFileDialog dialog(nullptr, webm ? "Save WEBM Sticker" : "Save GIF", suggestedPath, filter);
    dialog.setAcceptMode(QFileDialog::AcceptSave);
    dialog.setFileMode(QFileDialog::AnyFile);
    dialog.setDefaultSuffix(webm ? "webm" : "gif");
    dialog.setOption(QFileDialog::DontUseNativeDialog, false);
    if (!dialog.exec()) {
        return;
    }
    const QStringList files = dialog.selectedFiles();
    QString filePath = files.isEmpty() ? QString() : files.first();
    if (filePath.isEmpty()) {
        return;
    }
    if (webm) {
        if (!filePath.endsWith(".webm", Qt::CaseInsensitive)) {
            filePath += ".webm";
        }
    } else if (!filePath.endsWith(".gif", Qt::CaseInsensitive)) {
        filePath += ".gif";
    }
    settings.setValue(kLastExportPathKey, QFileInfo(filePath).absoluteFilePath());
    startConversion(filePath);
}

void AppController::openVideo(const QString &filePath) {
    clearMessages();
    QString normalizedPath = filePath.trimmed();
    const QUrl possibleUrl(normalizedPath);
    if (possibleUrl.isValid() && possibleUrl.scheme() == "file") {
        normalizedPath = possibleUrl.toLocalFile();
    }

    QFileInfo fi(normalizedPath);
    if (!fi.exists() || !fi.isFile()) {
        setError("Video file does not exist.");
        return;
    }

    QString probeError;
    const VideoInfo info = probeVideo(normalizedPath, &probeError);
    if (!probeError.isEmpty()) {
        setError(probeError);
        return;
    }

    m_videoPath = fi.absoluteFilePath();
    m_videoUrl = localFileUrl(m_videoPath);
    m_videoInfo = info;
    m_currentTime = 0.0;
    m_startTime = 0.0;
    m_endTime = info.duration;
    m_targetWidth = std::max(100, std::min(info.width, 480));
    m_targetFps = std::max(6, std::min(info.fps, 15));
    m_thumbnailCount = 0;
    m_thumbnailPoolCount = 0;
    m_pendingThumbnailCount = 0;
    m_thumbnailPoolUrls.clear();
    m_thumbnailsGenerated = 0;
    m_thumbWindowFrom = 0.0;
    m_thumbWindowTo = info.duration;
    m_thumbnailGenerating = false;
    ensureThumbnailsForCount(12);

    emit videoPathChanged();
    emit videoUrlChanged();
    emit videoMetaChanged();
    emit currentTimeChanged();
    emit trimChanged();
    emit settingsChanged();
    emit thumbnailsChanged();
}

void AppController::ensureThumbnailsForCount(int count) {
    ensureThumbnailsForWindow(count, 0.0, m_videoInfo.duration);
}

void AppController::ensureThumbnailsForWindow(int count, double fromSec, double toSec) {
    if (m_videoPath.isEmpty() || m_videoInfo.duration <= 0.0) {
        return;
    }
    const double visibleFrom = std::max(0.0, std::min(fromSec, m_videoInfo.duration));
    const double visibleTo = std::max(visibleFrom + 0.05, std::min(toSec, m_videoInfo.duration));
    const double visibleSpan = std::max(0.05, visibleTo - visibleFrom);
    const double quantStep = std::max(0.25, visibleSpan / 8.0);
    const double clampedFrom = std::max(0.0, std::floor(visibleFrom / quantStep) * quantStep);
    const double clampedTo = std::min(m_videoInfo.duration,
                                      std::max(clampedFrom + 0.05, std::ceil(visibleTo / quantStep) * quantStep));
    Q_UNUSED(count)
    const int clamped = kFixedThumbCount;
    const bool alreadyCoversVisible = !m_thumbnailUrls.isEmpty()
        && m_thumbWindowFrom <= visibleFrom + 0.02
        && m_thumbWindowTo >= visibleTo - 0.02;

    if (!m_thumbnailGenerating && clamped == m_thumbnailCount && alreadyCoversVisible
        && std::abs(m_thumbWindowFrom - clampedFrom) < quantStep * 0.5
        && std::abs(m_thumbWindowTo - clampedTo) < quantStep * 0.5) {
        return;
    }

    m_thumbWindowFrom = clampedFrom;
    m_thumbWindowTo = clampedTo;
    m_thumbRequestedSeq += 1;

    m_pendingThumbnailCount = clamped;
    if (!m_thumbnailGenerating) {
        startThumbnailGeneration(clamped);
    }
}

void AppController::startConversion(const QString &outputPath) {
    clearMessages();
    if (m_converting) {
        setError("Conversion is already running.");
        return;
    }
    if (m_videoPath.isEmpty()) {
        setError("No video selected.");
        return;
    }
    if (m_endTime <= m_startTime) {
        setError("Invalid trim range.");
        return;
    }
    QString normalizedOutputPath = outputPath.trimmed();
    const QUrl possibleUrl(normalizedOutputPath);
    if (possibleUrl.isValid() && possibleUrl.scheme() == "file") {
        normalizedOutputPath = possibleUrl.toLocalFile();
    }

    if (normalizedOutputPath.isEmpty()) {
        setError("Output path is empty.");
        return;
    }

    const double clipDuration = m_endTime - m_startTime;
    const QList<AttemptConfig> configs = buildConfigs(
        clipDuration,
        m_targetWidth,
        m_targetFps,
        kMaxGifSize
    );

    m_cancelRequested = false;
    setConverting(true);
    setProgress(0);

    bool success = false;
    if (m_stickerWebmMode) {
        const QList<int> crfConfigs = buildWebmCrfConfigs(clipDuration);
        for (int i = 0; i < crfConfigs.size(); ++i) {
            if (m_cancelRequested) {
                setError("Conversion cancelled.");
                break;
            }

            const int fps = std::max(6, std::min(m_targetFps - (i / 2) * 2, 30));
            const int width = std::max(100, std::min(m_targetWidth, 512));
            const int crf = crfConfigs.at(i);
            setProgress(int((double(i) / double(crfConfigs.size())) * 80.0));

            if (!runWebmStickerAttempt(m_videoPath, normalizedOutputPath, m_startTime, clipDuration, width, fps, crf)) {
                continue;
            }

            QFileInfo outInfo(normalizedOutputPath);
            if (outInfo.exists() && outInfo.size() <= kMaxStickerWebmSize) {
                success = true;
                setProgress(100);
                m_successMessage = "WEBM sticker saved successfully.";
                emit successMessageChanged();
                break;
            }

            QFile::remove(normalizedOutputPath);
        }

        if (!success && !m_cancelRequested && m_errorMessage.isEmpty()) {
            setError("Could not fit WEBM under 256KB. Try shorter clip.");
        }
    } else {
        for (int i = 0; i < configs.size(); ++i) {
            if (m_cancelRequested) {
                setError("Conversion cancelled.");
                break;
            }

            const auto cfg = configs.at(i);
            const int width = std::max(100, int(double(m_targetWidth) * cfg.scale));
            const int fps = std::max(6, m_targetFps + cfg.fpsMod);

            setProgress(int((double(i) / double(configs.size())) * 80.0));

            if (!runAttempt(m_videoPath, normalizedOutputPath, m_startTime, clipDuration, fps, width)) {
                continue;
            }

            QFileInfo outInfo(normalizedOutputPath);
            if (outInfo.exists() && outInfo.size() <= kMaxGifSize) {
                success = true;
                setProgress(100);
                m_successMessage = "GIF saved successfully.";
                emit successMessageChanged();
                break;
            }

            QFile::remove(normalizedOutputPath);
        }

        if (!success && !m_cancelRequested && m_errorMessage.isEmpty()) {
            setError("Could not fit GIF under 10MB. Try shorter clip.");
        }
    }

    setConverting(false);
}

void AppController::cancelConversion() {
    m_cancelRequested = true;
    if (m_activeFfmpeg) {
        m_activeFfmpeg->kill();
    }
}

void AppController::clearVideo() {
    if (m_converting) {
        cancelConversion();
    }
    const bool hadVideo = !m_videoPath.isEmpty();
    m_videoPath.clear();
    m_videoUrl.clear();
    m_videoInfo = {};
    m_currentTime = 0.0;
    m_startTime = 0.0;
    m_endTime = 0.0;
    m_targetWidth = 480;
    m_targetFps = 15;
    m_thumbnailCount = 0;
    m_thumbnailPoolCount = 0;
    m_pendingThumbnailCount = 0;
    m_thumbnailGenerating = false;
    if (m_thumbStepTimer.isActive()) {
        m_thumbStepTimer.stop();
    }
    if (m_thumbPlayer) {
        m_thumbPlayer->stop();
        m_thumbPlayer->deleteLater();
        m_thumbPlayer = nullptr;
    }
    if (m_thumbSink) {
        m_thumbSink->deleteLater();
        m_thumbSink = nullptr;
    }
    m_thumbWindowFrom = 0.0;
    m_thumbWindowTo = 0.0;
    m_thumbnailUrls.clear();
    m_thumbnailsGenerated = 0;
    m_thumbnailsVersion += 1;
    m_thumbnailPoolUrls.clear();
    setProgress(0);
    clearMessages();

    if (hadVideo) {
        emit videoPathChanged();
        emit videoUrlChanged();
        emit videoMetaChanged();
        emit currentTimeChanged();
        emit trimChanged();
        emit settingsChanged();
        emit thumbnailsChanged();
    }
}

void AppController::startThumbnailGeneration(int count) {
    if (m_videoPath.isEmpty() || m_videoInfo.duration <= 0.0) {
        return;
    }

    Q_UNUSED(count)
    m_thumbTargetCount = kFixedThumbCount;
    m_thumbnailGenerating = true;
    m_thumbRunningSeq = m_thumbRequestedSeq;

    QObject::disconnect(&m_thumbWatcher, nullptr, this, nullptr);
    const QString path = m_videoPath;
    const double fromSec = m_thumbWindowFrom;
    const double toSec = m_thumbWindowTo;
    const int runSeq = m_thumbRunningSeq;
    connect(&m_thumbWatcher, &QFutureWatcher<QStringList>::finished, this, [this, path, runSeq]() {
        if (path != m_videoPath) {
            return;
        }
        if (runSeq != m_thumbRequestedSeq) {
            m_thumbnailGenerating = false;
            startThumbnailGeneration(kFixedThumbCount);
            return;
        }
        const QStringList generated = m_thumbWatcher.result();
        m_thumbnailUrls = generated;
        m_thumbnailPoolUrls = generated;
        m_thumbnailPoolCount = generated.size();
        m_thumbnailCount = generated.size();
        m_thumbnailsGenerated = generated.size();
        m_pendingThumbnailCount = 0;
        m_thumbnailGenerating = false;
        m_thumbnailsVersion += 1;
        emit thumbnailsChanged();

        if (m_thumbRunningSeq != m_thumbRequestedSeq) {
            startThumbnailGeneration(kFixedThumbCount);
        }
    });

    const double duration = m_videoInfo.duration;
    const int targetCount = m_thumbTargetCount;
    m_thumbWatcher.setFuture(QtConcurrent::run([path, duration, targetCount, fromSec, toSec]() {
        return generateThumbnailsWithFfmpegFallback(path, duration, targetCount, fromSec, toSec);
    }));
}

void AppController::continueThumbnailGeneration() {
    // unused in ffmpeg mode
}

void AppController::onThumbnailStepTimeout() {
    // unused in ffmpeg mode
}

void AppController::finishThumbnailGeneration() {
    m_thumbnailGenerating = false;
}

void AppController::setCurrentTime(double value) {
    const double clamped = std::max(0.0, std::min(value, m_videoInfo.duration));
    if (qFuzzyCompare(clamped + 1.0, m_currentTime + 1.0)) {
        return;
    }
    m_currentTime = clamped;
    emit currentTimeChanged();
}

void AppController::setStartTime(double value) {
    const double clamped = std::max(0.0, std::min(value, m_endTime));
    if (qFuzzyCompare(clamped + 1.0, m_startTime + 1.0)) {
        return;
    }
    m_startTime = clamped;
    emit trimChanged();
    emit settingsChanged();
}

void AppController::setEndTime(double value) {
    const double clamped = std::max(m_startTime, std::min(value, m_videoInfo.duration));
    if (qFuzzyCompare(clamped + 1.0, m_endTime + 1.0)) {
        return;
    }
    m_endTime = clamped;
    emit trimChanged();
    emit settingsChanged();
}

void AppController::setTargetWidth(int value) {
    const int maxW = m_stickerWebmMode ? 512 : 1024;
    const int clamped = std::max(100, std::min(value, maxW));
    if (clamped == m_targetWidth) {
        return;
    }
    m_targetWidth = clamped;
    emit settingsChanged();
}

void AppController::setTargetFps(int value) {
    const int clamped = std::max(6, std::min(value, 30));
    if (clamped == m_targetFps) {
        return;
    }
    m_targetFps = clamped;
    emit settingsChanged();
}

void AppController::setStickerWebmMode(bool value) {
    if (m_stickerWebmMode == value) {
        return;
    }
    m_stickerWebmMode = value;
    if (m_stickerWebmMode && m_targetWidth > 512) {
        m_targetWidth = 512;
    }
    emit settingsChanged();
}

void AppController::setIncludeSubtitles(bool value) {
    if (m_includeSubtitles == value) {
        return;
    }
    m_includeSubtitles = value;
    emit settingsChanged();
}

void AppController::setSubtitleStreamIndex(int value) {
    if (m_subtitleStreamIndex == value) {
        return;
    }
    m_subtitleStreamIndex = value;
    emit settingsChanged();
}

int AppController::parseFps(const QString &rate) {
    if (rate.contains('/')) {
        const auto parts = rate.split('/');
        if (parts.size() == 2) {
            bool okNum = false;
            bool okDen = false;
            const double num = parts.at(0).toDouble(&okNum);
            const double den = parts.at(1).toDouble(&okDen);
            if (okNum && okDen && den > 0.0) {
                return std::max(1, int(num / den));
            }
        }
    }
    bool ok = false;
    const int val = int(rate.toDouble(&ok));
    return ok ? std::max(1, val) : 30;
}

double AppController::parseFfmpegTimeToSeconds(const QString &line) {
    static const QRegularExpression re(R"(time=(\d{2}):(\d{2}):(\d{2}\.\d+))");
    const auto match = re.match(line);
    if (!match.hasMatch()) {
        return -1.0;
    }
    const int hh = match.captured(1).toInt();
    const int mm = match.captured(2).toInt();
    const double ss = match.captured(3).toDouble();
    return double(hh * 3600 + mm * 60) + ss;
}

QList<AppController::AttemptConfig> AppController::buildConfigs(
    double clipDuration,
    int width,
    int fps,
    qint64 maxFileSize
) {
    const QList<AttemptConfig> all{
        {1.0, 0}, {0.75, 0}, {0.5, 0}, {0.75, -5}, {0.5, -5}, {0.35, -5}, {0.25, -10}
    };

    constexpr double bytesPerFrameAt480 = 25000.0;
    int startIdx = 0;
    for (int i = 0; i < all.size(); ++i) {
        const auto cfg = all.at(i);
        const int estWidth = int(double(width) * cfg.scale);
        const int estFps = std::max(6, fps + cfg.fpsMod);
        const double estSize = clipDuration * estFps * bytesPerFrameAt480 * std::pow(double(estWidth) / 480.0, 2.0);
        if (estSize <= double(maxFileSize) * 1.3) {
            startIdx = std::max(0, i - 1);
            break;
        }
        startIdx = i;
    }

    QList<AttemptConfig> sliced;
    for (int i = startIdx; i < all.size(); ++i) {
        sliced.push_back(all.at(i));
    }
    return sliced;
}

QList<int> AppController::buildWebmCrfConfigs(double clipDuration) {
    Q_UNUSED(clipDuration)
    return QList<int>{30, 34, 38, 42, 46, 50, 54, 58, 60};
}

QStringList AppController::subtitleFilterPrefixes(double startTime, QString *error) const {
    if (error) {
        error->clear();
    }
    if (!m_includeSubtitles || m_videoPath.isEmpty()) {
        return QStringList{QString()};
    }

    if (m_subtitleStreamIndex < 0) {
        if (error) {
            *error = "Enable subtitle track first (not Off).";
        }
        return {};
    }

    QString normalizedPath = QDir::fromNativeSeparators(m_videoPath);
    normalizedPath.replace("'", "\\'");
    normalizedPath.replace(":", "\\:");

    const QString shift = QString::number(std::max(0.0, startTime), 'f', 3);
    return QStringList{
        QString("setpts=PTS+%1/TB,subtitles='%2':si=%3,setpts=PTS-%1/TB,")
            .arg(shift)
            .arg(normalizedPath)
            .arg(m_subtitleStreamIndex)
    };
}

QString AppController::localFileUrl(const QString &path) {
    return QUrl::fromLocalFile(path).toString();
}

AppController::VideoInfo AppController::probeVideo(const QString &path, QString *error) const {
    QProcess proc;
    QStringList args{
        "-v", "error",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        path
    };
    proc.start(bundledToolPath(QStringLiteral("ffprobe")), args);
    if (!proc.waitForStarted(3000)) {
        *error = "Cannot start ffprobe. Install ffmpeg/ffprobe.";
        return {};
    }
    proc.waitForFinished(10000);
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        *error = "ffprobe failed for selected file.";
        return {};
    }

    const QJsonDocument doc = QJsonDocument::fromJson(proc.readAllStandardOutput());
    if (!doc.isObject()) {
        *error = "Invalid ffprobe output.";
        return {};
    }
    const QJsonObject root = doc.object();
    const QJsonArray streams = root.value("streams").toArray();
    VideoInfo info;

    QJsonObject videoStream;
    for (const auto &v : streams) {
        const QJsonObject s = v.toObject();
        if (s.value("codec_type").toString() == "video") {
            videoStream = s;
        }
        if (s.value("codec_type").toString() == "subtitle") {
            const int streamIdx = s.value("index").toInt(-1);
            if (streamIdx >= 0) {
                info.subtitleStreamIndexes.push_back(streamIdx);
            }
        }
    }
    if (videoStream.isEmpty()) {
        *error = "No video stream found.";
        return {};
    }

    const QJsonObject format = root.value("format").toObject();

    info.duration = format.value("duration").toString().toDouble();
    info.width = videoStream.value("width").toInt();
    info.height = videoStream.value("height").toInt();
    info.fps = parseFps(videoStream.value("r_frame_rate").toString("30/1"));
    info.codec = videoStream.value("codec_name").toString("unknown");
    info.size = QFileInfo(path).size();

    if (info.duration <= 0.0) {
        *error = "Could not determine video duration.";
        return {};
    }
    return info;
}

bool AppController::runAttempt(const QString &inputPath,
                               const QString &outputPath,
                               double startTime,
                               double clipDuration,
                               int fps,
                               int width) {
    QString subtitleError;
    const QStringList subtitlePrefixes = subtitleFilterPrefixes(startTime, &subtitleError);
    if (subtitlePrefixes.isEmpty()) {
        if (!subtitleError.isEmpty()) {
            setError(subtitleError);
        }
        return false;
    }
    for (int attemptIdx = 0; attemptIdx < subtitlePrefixes.size(); ++attemptIdx) {
        QProcess proc;
        m_activeFfmpeg = &proc;

        const QString filter = QString(
            "%1fps=%2,scale=%3:-1:flags=lanczos,split[s0][s1];"
            "[s0]palettegen=max_colors=256:stats_mode=diff[p];"
            "[s1][p]paletteuse=dither=bayer:bayer_scale=5"
        ).arg(subtitlePrefixes.at(attemptIdx)).arg(fps).arg(width);

        QStringList args{
            "-y",
            "-ss", QString::number(startTime, 'f', 3),
            "-t", QString::number(clipDuration, 'f', 3),
            "-i", inputPath,
            "-filter_complex", filter,
            outputPath
        };

        proc.start(bundledToolPath(QStringLiteral("ffmpeg")), args);
        if (!proc.waitForStarted(3000)) {
            m_activeFfmpeg = nullptr;
            setError("Cannot start ffmpeg. Install ffmpeg.");
            return false;
        }

        QString fullErr;
        while (proc.state() == QProcess::Running) {
            if (m_cancelRequested) {
                proc.kill();
                proc.waitForFinished(2000);
                m_activeFfmpeg = nullptr;
                return false;
            }
            proc.waitForReadyRead(200);
            const QString errOut = QString::fromLocal8Bit(proc.readAllStandardError());
            if (!errOut.isEmpty()) {
                fullErr += errOut;
            }
            const QStringList lines = errOut.split('\n', Qt::SkipEmptyParts);
            for (const QString &line : lines) {
                const double sec = parseFfmpegTimeToSeconds(line);
                if (sec >= 0.0 && clipDuration > 0.0) {
                    const int pct = std::min(99, int((sec / clipDuration) * 100.0));
                    setProgress(std::max(m_progress, pct));
                }
            }
            QCoreApplication::processEvents();
        }

        proc.waitForFinished();
        const QString tailErr = QString::fromLocal8Bit(proc.readAllStandardError());
        if (!tailErr.isEmpty()) {
            fullErr += tailErr;
        }
        const bool ok = proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
        m_activeFfmpeg = nullptr;
        if (ok) {
            return true;
        }

        if (!fullErr.isEmpty()) {
            setError(QString("ffmpeg failed: %1").arg(fullErr.split('\n', Qt::SkipEmptyParts).last()));
        } else if (m_includeSubtitles) {
            setError("Subtitle burn failed for selected track.");
        }
    }
    return false;
}

bool AppController::runWebmStickerAttempt(const QString &inputPath,
                                          const QString &outputPath,
                                          double startTime,
                                          double clipDuration,
                                          int width,
                                          int fps,
                                          int crf) {
    QString subtitleError;
    const QStringList subtitlePrefixes = subtitleFilterPrefixes(startTime, &subtitleError);
    if (subtitlePrefixes.isEmpty()) {
        if (!subtitleError.isEmpty()) {
            setError(subtitleError);
        }
        return false;
    }
    for (int attemptIdx = 0; attemptIdx < subtitlePrefixes.size(); ++attemptIdx) {
        QProcess proc;
        m_activeFfmpeg = &proc;

        const QString filter = QString(
            "%1fps=%2,scale=%3:%3:force_original_aspect_ratio=decrease:flags=lanczos"
        ).arg(subtitlePrefixes.at(attemptIdx)).arg(fps).arg(width);

        QStringList args{
            "-y",
            "-ss", QString::number(startTime, 'f', 3),
            "-t", QString::number(std::min(clipDuration, 3.0), 'f', 3),
            "-i", inputPath,
            "-an",
            "-vf", filter,
            "-c:v", "libvpx-vp9",
            "-pix_fmt", "yuv420p",
            "-b:v", "0",
            "-crf", QString::number(crf),
            "-row-mt", "1",
            "-threads", "4",
            outputPath
        };

        proc.start(bundledToolPath(QStringLiteral("ffmpeg")), args);
        if (!proc.waitForStarted(3000)) {
            m_activeFfmpeg = nullptr;
            setError("Cannot start ffmpeg. Install ffmpeg.");
            return false;
        }

        QString fullErr;
        while (proc.state() == QProcess::Running) {
            if (m_cancelRequested) {
                proc.kill();
                proc.waitForFinished(2000);
                m_activeFfmpeg = nullptr;
                return false;
            }
            proc.waitForReadyRead(200);
            const QString errOut = QString::fromLocal8Bit(proc.readAllStandardError());
            if (!errOut.isEmpty()) {
                fullErr += errOut;
            }
            const QStringList lines = errOut.split('\n', Qt::SkipEmptyParts);
            for (const QString &line : lines) {
                const double sec = parseFfmpegTimeToSeconds(line);
                if (sec >= 0.0 && clipDuration > 0.0) {
                    const int pct = std::min(99, int((sec / clipDuration) * 100.0));
                    setProgress(std::max(m_progress, pct));
                }
            }
            QCoreApplication::processEvents();
        }

        proc.waitForFinished();
        const QString tailErr = QString::fromLocal8Bit(proc.readAllStandardError());
        if (!tailErr.isEmpty()) {
            fullErr += tailErr;
        }
        const bool ok = proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
        m_activeFfmpeg = nullptr;
        if (ok) {
            return true;
        }

        if (!fullErr.isEmpty()) {
            setError(QString("ffmpeg failed: %1").arg(fullErr.split('\n', Qt::SkipEmptyParts).last()));
        } else if (m_includeSubtitles) {
            setError("Subtitle burn failed for selected track.");
        }
    }
    return false;
}

void AppController::setError(const QString &message) {
    if (m_errorMessage == message) {
        return;
    }
    m_errorMessage = message;
    emit errorMessageChanged();
}

void AppController::clearMessages() {
    if (!m_errorMessage.isEmpty()) {
        m_errorMessage.clear();
        emit errorMessageChanged();
    }
    if (!m_successMessage.isEmpty()) {
        m_successMessage.clear();
        emit successMessageChanged();
    }
}

void AppController::setConverting(bool value) {
    if (m_converting == value) {
        return;
    }
    m_converting = value;
    emit conversionStateChanged();
}

void AppController::setProgress(int value) {
    const int clamped = std::max(0, std::min(value, 100));
    if (m_progress == clamped) {
        return;
    }
    m_progress = clamped;
    emit conversionStateChanged();
}
