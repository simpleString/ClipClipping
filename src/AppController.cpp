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
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>
#include <cmath>

namespace {
constexpr qint64 kMaxGifSize = 10 * 1024 * 1024;
}

AppController::AppController(QObject *parent) : QObject(parent) {}

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
bool AppController::converting() const { return m_converting; }
int AppController::progress() const { return m_progress; }
QStringList AppController::thumbnailUrls() const { return m_thumbnailUrls; }
QString AppController::errorMessage() const { return m_errorMessage; }
QString AppController::successMessage() const { return m_successMessage; }
double AppController::estimatedSizeMb() const {
    const double clipDuration = std::max(0.0, m_endTime - m_startTime);
    const double est = (double(m_targetWidth) / 480.0) * (double(m_targetFps) / 15.0) * clipDuration * 0.8;
    return est;
}

bool AppController::hasVideo() const {
    return !m_videoPath.isEmpty();
}

void AppController::openVideoDialog() {
    const QString filter = "Video files (*.mp4 *.avi *.mkv *.mov *.webm *.flv *.wmv *.ts *.m4v);;All files (*)";
    const QString filePath = QFileDialog::getOpenFileName(nullptr, "Select Video", QString(), filter);
    if (filePath.isEmpty()) {
        return;
    }
    openVideo(filePath);
}

void AppController::openSaveGifDialog() {
    const QString filter = "GIF files (*.gif)";
    QString filePath = QFileDialog::getSaveFileName(nullptr, "Save GIF", "output.gif", filter);
    if (filePath.isEmpty()) {
        return;
    }
    if (!filePath.endsWith(".gif", Qt::CaseInsensitive)) {
        filePath += ".gif";
    }
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
    const VideoInfo info = probeVideo(filePath, &probeError);
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
    generateThumbnails(m_videoPath, info.duration);

    emit videoPathChanged();
    emit videoUrlChanged();
    emit videoMetaChanged();
    emit currentTimeChanged();
    emit trimChanged();
    emit settingsChanged();
    emit thumbnailsChanged();
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
    m_thumbnailUrls.clear();
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

void AppController::generateThumbnails(const QString &inputPath, double duration) {
    m_thumbnailUrls.clear();
    if (duration <= 0.0) {
        return;
    }

    const QString tmpRoot = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (tmpRoot.isEmpty()) {
        return;
    }

    const QByteArray key = inputPath.toUtf8() + QByteArray::number(QFileInfo(inputPath).size());
    const QString hash = QString::fromLatin1(QCryptographicHash::hash(key, QCryptographicHash::Md5).toHex());
    const QString dirPath = QDir(tmpRoot).filePath(QStringLiteral("telegramgifterqt_thumbs/%1").arg(hash));
    QDir dir(dirPath);
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    const int thumbCount = 12;
    for (int i = 0; i < thumbCount; ++i) {
        const double pos = (duration * (double(i) + 0.5)) / double(thumbCount);
        const QString outPath = dir.filePath(QStringLiteral("thumb_%1.jpg").arg(i, 2, 10, QChar('0')));

        if (!QFileInfo::exists(outPath)) {
            QProcess proc;
            QStringList args{
                "-y",
                "-ss", QString::number(pos, 'f', 3),
                "-i", inputPath,
                "-frames:v", "1",
                "-vf", "scale=160:-2",
                outPath
            };
            proc.start("ffmpeg", args);
            if (!proc.waitForStarted(2000)) {
                continue;
            }
            proc.waitForFinished(8000);
            if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
                continue;
            }
        }

        if (QFileInfo::exists(outPath)) {
            m_thumbnailUrls.push_back(QUrl::fromLocalFile(outPath).toString());
        }
    }
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
    const int maxW = std::max(100, std::max(m_videoInfo.width, 100));
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
    proc.start("ffprobe", args);
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

    QJsonObject videoStream;
    for (const auto &v : streams) {
        const QJsonObject s = v.toObject();
        if (s.value("codec_type").toString() == "video") {
            videoStream = s;
            break;
        }
    }
    if (videoStream.isEmpty()) {
        *error = "No video stream found.";
        return {};
    }

    const QJsonObject format = root.value("format").toObject();

    VideoInfo info;
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
    QProcess proc;
    m_activeFfmpeg = &proc;

    const QString filter = QString(
        "fps=%1,scale=%2:-1:flags=lanczos,split[s0][s1];"
        "[s0]palettegen=max_colors=256:stats_mode=diff[p];"
        "[s1][p]paletteuse=dither=bayer:bayer_scale=5"
    ).arg(fps).arg(width);

    QStringList args{
        "-y",
        "-ss", QString::number(startTime, 'f', 3),
        "-t", QString::number(clipDuration, 'f', 3),
        "-i", inputPath,
        "-filter_complex", filter,
        outputPath
    };

    proc.start("ffmpeg", args);
    if (!proc.waitForStarted(3000)) {
        m_activeFfmpeg = nullptr;
        setError("Cannot start ffmpeg. Install ffmpeg.");
        return false;
    }

    while (proc.state() == QProcess::Running) {
        if (m_cancelRequested) {
            proc.kill();
            proc.waitForFinished(2000);
            m_activeFfmpeg = nullptr;
            return false;
        }
        proc.waitForReadyRead(200);
        const QString errOut = QString::fromLocal8Bit(proc.readAllStandardError());
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
    const bool ok = proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
    m_activeFfmpeg = nullptr;
    return ok;
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
