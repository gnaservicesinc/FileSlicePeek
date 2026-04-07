#include "hexdocumentmodel.h"

#include <QClipboard>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QMimeDatabase>
#include <QRegularExpression>
#include <QSaveFile>

namespace {
QString printableCharacter(unsigned char value)
{
    if (value >= 32 && value <= 126) {
        return QString(QChar(value));
    }

    if (value == '\t') {
        return QStringLiteral("⇥");
    }

    if (value == '\n') {
        return QStringLiteral("↩");
    }

    if (value == '\r') {
        return QStringLiteral("␍");
    }

    return QStringLiteral("·");
}

QString hexByte(unsigned char value)
{
    return QStringLiteral("%1").arg(value, 2, 16, QChar('0')).toUpper();
}
}

HexDocumentModel::HexDocumentModel(QObject *parent)
    : QObject(parent)
{
}

bool HexDocumentModel::hasFile() const { return m_hasFile; }
bool HexDocumentModel::dirty() const { return m_dirty; }
bool HexDocumentModel::base64Ready() const { return m_base64Ready; }
bool HexDocumentModel::loading() const { return m_loading; }
QString HexDocumentModel::displayName() const { return m_displayName; }
QString HexDocumentModel::visiblePath() const { return m_visiblePath; }
QString HexDocumentModel::kindDescription() const { return m_metadata.kindDescription; }
QString HexDocumentModel::sizeDescription() const { return m_metadata.sizeDescription; }
QString HexDocumentModel::ownerName() const { return m_metadata.ownerName; }
QString HexDocumentModel::groupName() const { return m_metadata.groupName; }
QString HexDocumentModel::createdText() const { return m_metadata.createdText; }
QString HexDocumentModel::modifiedText() const { return m_metadata.modifiedText; }
QString HexDocumentModel::md5Hash() const { return m_hashes.md5; }
QString HexDocumentModel::sha1Hash() const { return m_hashes.sha1; }
QString HexDocumentModel::sha256Hash() const { return m_hashes.sha256; }
QString HexDocumentModel::statusText() const { return m_statusText; }
QString HexDocumentModel::errorMessage() const { return m_errorMessage; }
QString HexDocumentModel::findQuery() const { return m_findQuery; }
QString HexDocumentModel::replaceQuery() const { return m_replaceQuery; }
QString HexDocumentModel::jumpQuery() const { return m_jumpQuery; }
QString HexDocumentModel::searchMode() const { return m_searchMode; }
QString HexDocumentModel::selectedHexText() const
{
    if (m_selectedOffset < 0 || m_workingData.isEmpty()) {
        return {};
    }

    QStringList values;
    const int length = qMin(m_selectionLength, m_workingData.size() - m_selectedOffset);
    values.reserve(length);
    for (int index = 0; index < length; ++index) {
        values << hexByte(static_cast<unsigned char>(m_workingData.at(m_selectedOffset + index)));
    }
    return values.join(QLatin1Char(' '));
}

QString HexDocumentModel::selectedTextText() const
{
    if (m_selectedOffset < 0 || m_workingData.isEmpty()) {
        return {};
    }

    const int length = qMin(m_selectionLength, m_workingData.size() - m_selectedOffset);
    return QString::fromUtf8(m_workingData.mid(m_selectedOffset, length));
}
int HexDocumentModel::rowCount() const { return m_rowCount; }
int HexDocumentModel::dataCount() const { return m_workingData.size(); }
int HexDocumentModel::selectedOffset() const { return m_selectedOffset; }
int HexDocumentModel::selectionLength() const { return m_selectionLength; }
int HexDocumentModel::revision() const { return m_revision; }

void HexDocumentModel::setFindQuery(const QString &value)
{
    if (m_findQuery == value) {
        return;
    }

    m_findQuery = value;
    emit searchInputsChanged();
}

void HexDocumentModel::setReplaceQuery(const QString &value)
{
    if (m_replaceQuery == value) {
        return;
    }

    m_replaceQuery = value;
    emit searchInputsChanged();
}

void HexDocumentModel::setJumpQuery(const QString &value)
{
    if (m_jumpQuery == value) {
        return;
    }

    m_jumpQuery = value;
    emit selectionChanged();
}

void HexDocumentModel::setSearchMode(const QString &value)
{
    const auto normalized = value.toLower() == QStringLiteral("text") ? QStringLiteral("text") : QStringLiteral("hex");
    if (m_searchMode == normalized) {
        return;
    }

    m_searchMode = normalized;
    emit searchInputsChanged();
}

void HexDocumentModel::setSelectionLength(int value)
{
    const int clamped = qMax(1, value);
    if (m_selectionLength == clamped) {
        return;
    }

    m_selectionLength = clamped;
    normalizeSelection();
    ++m_revision;
    emit revisionChanged();
    emit selectionChanged();
}

void HexDocumentModel::openFile(const QUrl &fileUrl)
{
    if (!fileUrl.isValid()) {
        setError(QStringLiteral("Choose a file first."));
        return;
    }

    try {
        const QString inspectablePath = resolveInspectablePath(fileUrl);
        QFile file(inspectablePath);

        if (!file.open(QIODevice::ReadOnly)) {
            setError(file.errorString());
            return;
        }

        m_loading = true;
        emit loadingChanged();

        m_originalData = file.readAll();
        m_workingData = m_originalData;
        m_sourceUrl = fileUrl;
        m_displayName = QFileInfo(fileUrl.toLocalFile()).fileName();
        m_visiblePath = fileUrl.toLocalFile();
        m_hasFile = true;
        m_dirty = false;
        m_selectedOffset = m_workingData.isEmpty() ? -1 : 0;
        m_selectionLength = m_workingData.isEmpty() ? 1 : 1;
        m_rowCount = qMax(1, (m_workingData.size() + kBytesPerRow - 1) / kBytesPerRow);
        m_jumpQuery = QStringLiteral("0x0");
        m_base64Cache.clear();
        m_base64Ready = false;
        ++m_revision;

        refreshMetadata(QFileInfo(fileUrl.toLocalFile()), QFileInfo(inspectablePath));
        refreshHashes();

        m_loading = false;
        emit loadingChanged();
        emit fileChanged();
        emit dirtyChanged();
        emit base64ReadyChanged();
        emit bufferChanged();
        emit selectionChanged();
        emit revisionChanged();
        setStatus(QStringLiteral("Loaded %1 (%2).").arg(m_displayName, m_metadata.sizeDescription));
    } catch (const std::runtime_error &error) {
        setError(QString::fromUtf8(error.what()));
    }
}

void HexDocumentModel::save()
{
    if (!m_hasFile) {
        setStatus(QStringLiteral("Open a file first."));
        return;
    }

    QSaveFile file(m_sourceUrl.toLocalFile());
    if (!file.open(QIODevice::WriteOnly)) {
        setError(file.errorString());
        return;
    }

    file.write(m_workingData);
    if (!file.commit()) {
        setError(file.errorString());
        return;
    }

    m_originalData = m_workingData;
    m_dirty = false;
    emit dirtyChanged();
    refreshMetadata(QFileInfo(m_sourceUrl.toLocalFile()), QFileInfo(resolveInspectablePath(m_sourceUrl)));
    refreshHashes();
    setStatus(QStringLiteral("Saved %1.").arg(m_displayName));
}

void HexDocumentModel::revert()
{
    if (!m_hasFile) {
        return;
    }

    m_workingData = m_originalData;
    m_dirty = false;
    m_base64Ready = false;
    m_base64Cache.clear();
    normalizeSelection();
    m_rowCount = qMax(1, (m_workingData.size() + kBytesPerRow - 1) / kBytesPerRow);
    ++m_revision;
    emit dirtyChanged();
    emit base64ReadyChanged();
    emit bufferChanged();
    emit selectionChanged();
    emit revisionChanged();
    refreshHashes();
    setStatus(QStringLiteral("Reverted unsaved changes."));
}

void HexDocumentModel::moveSelection()
{
    try {
        const int offset = parseOffset(m_jumpQuery);
        selectOffset(offset);
    } catch (const std::runtime_error &error) {
        setError(QString::fromUtf8(error.what()));
    }
}

void HexDocumentModel::selectOffset(int offset)
{
    if (offset < 0 || offset >= m_workingData.size()) {
        setError(QStringLiteral("That offset is outside the current file."));
        return;
    }

    m_selectedOffset = offset;
    m_selectionLength = 1;
    normalizeSelection();
    m_jumpQuery = QStringLiteral("0x%1").arg(offset, 0, 16).toUpper();
    ++m_revision;
    emit revisionChanged();
    emit selectionChanged();
    setStatus(QStringLiteral("Selection moved to %1.").arg(formatOffset(offset)));
}

void HexDocumentModel::applyHexEdit(const QString &value)
{
    try {
        const QByteArray replacement = parseInput(value, true, true);
        if (m_selectedOffset < 0) {
            throw std::runtime_error("Choose a byte range first.");
        }

        const int length = qMin(m_selectionLength, m_workingData.size() - m_selectedOffset);
        m_workingData.replace(m_selectedOffset, length, replacement);
        m_selectionLength = qMax(1, replacement.size());
        markBufferChanged(QStringLiteral("Updated the selection using hex bytes."));
    } catch (const std::runtime_error &error) {
        setError(QString::fromUtf8(error.what()));
    }
}

void HexDocumentModel::applyTextEdit(const QString &value)
{
    if (m_selectedOffset < 0) {
        setError(QStringLiteral("Choose a byte range first."));
        return;
    }

    const QByteArray replacement = value.toUtf8();
    const int length = qMin(m_selectionLength, m_workingData.size() - m_selectedOffset);
    m_workingData.replace(m_selectedOffset, length, replacement);
    m_selectionLength = qMax(1, replacement.size());
    markBufferChanged(QStringLiteral("Updated the selection using text."));
}

int HexDocumentModel::replaceHexInput(const QString &value, int offset, int length)
{
    if (offset < 0 || offset >= m_workingData.size()) {
        return 0;
    }

    try {
        const QByteArray replacement = parseInput(value, true, true);
        return replaceBytes(offset, length, replacement, QStringLiteral("Updated bytes from the hex view."));
    } catch (const std::runtime_error &error) {
        setError(QString::fromUtf8(error.what()));
        return 0;
    }
}

int HexDocumentModel::replaceTextInput(const QString &value, int offset, int length)
{
    if (offset < 0 || offset >= m_workingData.size()) {
        return 0;
    }

    return replaceBytes(offset, length, value.toUtf8(), QStringLiteral("Updated bytes from the text view."));
}

void HexDocumentModel::findNext()
{
    try {
        const QByteArray pattern = parseInput(m_findQuery, false, m_searchMode == QStringLiteral("hex"));
        if (!selectMatch(pattern, SearchDirection::Forward)) {
            setStatus(QStringLiteral("No matches found."));
        }
    } catch (const std::runtime_error &error) {
        setError(QString::fromUtf8(error.what()));
    }
}

void HexDocumentModel::findPrevious()
{
    try {
        const QByteArray pattern = parseInput(m_findQuery, false, m_searchMode == QStringLiteral("hex"));
        if (!selectMatch(pattern, SearchDirection::Backward)) {
            setStatus(QStringLiteral("No matches found."));
        }
    } catch (const std::runtime_error &error) {
        setError(QString::fromUtf8(error.what()));
    }
}

void HexDocumentModel::replaceOne()
{
    replaceCurrent(false);
}

void HexDocumentModel::replaceOneAndFind()
{
    replaceCurrent(true);
}

void HexDocumentModel::replaceAll()
{
    try {
        const QByteArray pattern = parseInput(m_findQuery, false, m_searchMode == QStringLiteral("hex"));
        const QByteArray replacement = parseInput(m_replaceQuery, true, m_searchMode == QStringLiteral("hex"));

        int replacements = 0;
        int cursor = 0;
        int lastOffset = -1;

        while (cursor <= m_workingData.size()) {
            const int match = m_workingData.indexOf(pattern, cursor);
            if (match < 0) {
                break;
            }

            m_workingData.replace(match, pattern.size(), replacement);
            cursor = match + replacement.size();
            lastOffset = match;
            ++replacements;
        }

        if (replacements == 0) {
            setStatus(QStringLiteral("No matches were replaced."));
            return;
        }

        m_selectedOffset = lastOffset;
        m_selectionLength = qMax(1, replacement.size());
        markBufferChanged(QStringLiteral("Replaced %1 match%2.")
                              .arg(replacements)
                              .arg(replacements == 1 ? QString() : QStringLiteral("es")));
    } catch (const std::runtime_error &error) {
        setError(QString::fromUtf8(error.what()));
    }
}

void HexDocumentModel::exportHex(const QUrl &destinationUrl)
{
    QFile file(destinationUrl.toLocalFile());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        setError(file.errorString());
        return;
    }

    file.write(hexDump().toUtf8());
    setStatus(QStringLiteral("Saved %1.").arg(QFileInfo(destinationUrl.toLocalFile()).fileName()));
}

void HexDocumentModel::exportText(const QUrl &destinationUrl)
{
    QFile file(destinationUrl.toLocalFile());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        setError(file.errorString());
        return;
    }

    file.write(decodedText().toUtf8());
    setStatus(QStringLiteral("Saved %1.").arg(QFileInfo(destinationUrl.toLocalFile()).fileName()));
}

void HexDocumentModel::exportBase64(const QUrl &destinationUrl)
{
    ensureBase64();

    QFile file(destinationUrl.toLocalFile());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        setError(file.errorString());
        return;
    }

    file.write(m_base64Cache.toUtf8());
    setStatus(QStringLiteral("Saved %1.").arg(QFileInfo(destinationUrl.toLocalFile()).fileName()));
}

void HexDocumentModel::copyText(const QString &value)
{
    if (QClipboard *clipboard = QGuiApplication::clipboard()) {
        clipboard->setText(value);
        setStatus(QStringLiteral("Copied to the clipboard."));
    }
}

void HexDocumentModel::copySelection(const QString &mode)
{
    if (m_selectedOffset < 0 || m_workingData.isEmpty()) {
        setStatus(QStringLiteral("Choose bytes first."));
        return;
    }

    if (mode.compare(QStringLiteral("text"), Qt::CaseInsensitive) == 0) {
        copyText(visibleSelectionText());
        setStatus(QStringLiteral("Copied text bytes."));
        return;
    }

    copyText(selectedHexText());
    setStatus(QStringLiteral("Copied hex bytes."));
}

void HexDocumentModel::copyBase64()
{
    ensureBase64();
    copyText(m_base64Cache);
    setStatus(QStringLiteral("Copied Base64."));
}

void HexDocumentModel::clearError()
{
    if (m_errorMessage.isEmpty()) {
        return;
    }

    m_errorMessage.clear();
    emit errorChanged();
}

QString HexDocumentModel::addressForRow(int row) const
{
    return formatOffset(row * kBytesPerRow);
}

bool HexDocumentModel::cellExists(int row, int column) const
{
    const int offset = row * kBytesPerRow + column;
    return offset >= 0 && offset < m_workingData.size();
}

QString HexDocumentModel::hexValueAt(int row, int column) const
{
    if (!cellExists(row, column)) {
        return QStringLiteral("  ");
    }

    const auto value = static_cast<unsigned char>(m_workingData.at(row * kBytesPerRow + column));
    return hexByte(value);
}

QString HexDocumentModel::asciiValueAt(int row, int column) const
{
    if (!cellExists(row, column)) {
        return QStringLiteral(" ");
    }

    const auto value = static_cast<unsigned char>(m_workingData.at(row * kBytesPerRow + column));
    return printableCharacter(value);
}

bool HexDocumentModel::isOffsetSelected(int offset) const
{
    if (m_selectedOffset < 0) {
        return false;
    }

    return offset >= m_selectedOffset && offset < (m_selectedOffset + m_selectionLength);
}

QString HexDocumentModel::resolveInspectablePath(const QUrl &fileUrl) const
{
    const QString sourcePath = fileUrl.toLocalFile();
    QFileInfo info(sourcePath);

    if (!info.exists()) {
        throw std::runtime_error("That item no longer exists.");
    }

    if (!info.isDir()) {
        return sourcePath;
    }

    if (info.suffix().toLower() == QStringLiteral("app")) {
        QDir executableDir(info.filePath() + QStringLiteral("/Contents/MacOS"));
        const QStringList executables = executableDir.entryList(QDir::Files | QDir::NoDotAndDotDot);
        if (!executables.isEmpty()) {
            return executableDir.filePath(executables.first());
        }
    }

    throw std::runtime_error("Directories cannot be inspected directly. Choose a file or application bundle.");
}

QByteArray HexDocumentModel::parseInput(const QString &value, bool allowEmpty, bool useHexMode) const
{
    if (!useHexMode) {
        if (!allowEmpty && value.trimmed().isEmpty()) {
            throw std::runtime_error("Enter a value first.");
        }
        return value.toUtf8();
    }

    QString cleaned = value.trimmed();
    cleaned.remove(QStringLiteral("0x"), Qt::CaseInsensitive);
    cleaned.remove(QRegularExpression(QStringLiteral("[^0-9A-Fa-f]")));

    if (cleaned.isEmpty()) {
        if (allowEmpty) {
            return {};
        }
        throw std::runtime_error("Enter a hex value first.");
    }

    if (cleaned.size() % 2 != 0) {
        throw std::runtime_error("Hex values must be entered in pairs.");
    }

    QByteArray output;
    output.reserve(cleaned.size() / 2);

    for (int index = 0; index < cleaned.size(); index += 2) {
        bool ok = false;
        const auto byte = cleaned.mid(index, 2).toUInt(&ok, 16);
        if (!ok) {
            throw std::runtime_error("Invalid hex input.");
        }
        output.append(static_cast<char>(byte));
    }

    return output;
}

int HexDocumentModel::parseOffset(const QString &value) const
{
    const QString trimmed = value.trimmed();
    if (trimmed.isEmpty()) {
        throw std::runtime_error("Enter an offset first.");
    }

    bool ok = false;
    int offset = 0;

    if (trimmed.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive)) {
        offset = trimmed.mid(2).toInt(&ok, 16);
    } else if (trimmed.startsWith(QLatin1Char('$'))) {
        offset = trimmed.mid(1).toInt(&ok, 16);
    } else if (trimmed.endsWith(QLatin1Char('h'), Qt::CaseInsensitive)) {
        offset = trimmed.left(trimmed.size() - 1).toInt(&ok, 16);
    } else if (trimmed.contains(QRegularExpression(QStringLiteral("[A-Fa-f]")))) {
        offset = trimmed.toInt(&ok, 16);
    } else {
        offset = trimmed.toInt(&ok, 10);
    }

    if (!ok || offset < 0 || offset >= m_workingData.size()) {
        throw std::runtime_error("That offset is outside the current file.");
    }

    return offset;
}

void HexDocumentModel::setError(const QString &message)
{
    m_errorMessage = message;
    emit errorChanged();
    setStatus(message);
}

void HexDocumentModel::setStatus(const QString &message)
{
    m_statusText = message;
    emit statusChanged();
}

void HexDocumentModel::markBufferChanged(const QString &message)
{
    m_dirty = true;
    m_base64Ready = false;
    m_base64Cache.clear();
    m_rowCount = qMax(1, (m_workingData.size() + kBytesPerRow - 1) / kBytesPerRow);
    normalizeSelection();
    refreshHashes();
    ++m_revision;
    emit dirtyChanged();
    emit base64ReadyChanged();
    emit bufferChanged();
    emit selectionChanged();
    emit revisionChanged();
    setStatus(message);
}

void HexDocumentModel::normalizeSelection()
{
    if (m_workingData.isEmpty()) {
        m_selectedOffset = -1;
        m_selectionLength = 1;
        return;
    }

    if (m_selectedOffset < 0) {
        m_selectedOffset = 0;
    }

    if (m_selectedOffset >= m_workingData.size()) {
        m_selectedOffset = m_workingData.size() - 1;
    }

    m_selectionLength = qBound(1, m_selectionLength, m_workingData.size() - m_selectedOffset);
}

bool HexDocumentModel::selectMatch(const QByteArray &pattern, SearchDirection direction)
{
    if (pattern.isEmpty() || m_workingData.isEmpty()) {
        return false;
    }

    int match = -1;
    if (direction == SearchDirection::Forward) {
        const int start = qBound(0, m_selectedOffset + m_selectionLength, m_workingData.size());
        match = m_workingData.indexOf(pattern, start);
        if (match < 0) {
            match = m_workingData.indexOf(pattern, 0);
        }
    } else {
        const int end = qMax(0, m_selectedOffset);
        match = m_workingData.lastIndexOf(pattern, end - 1);
        if (match < 0) {
            match = m_workingData.lastIndexOf(pattern);
        }
    }

    if (match < 0) {
        return false;
    }

    m_selectedOffset = match;
    m_selectionLength = qMax(1, pattern.size());
    m_jumpQuery = QStringLiteral("0x%1").arg(match, 0, 16).toUpper();
    ++m_revision;
    emit revisionChanged();
    emit selectionChanged();
    setStatus(QStringLiteral("Match at %1.").arg(formatOffset(match)));
    return true;
}

bool HexDocumentModel::selectionMatches(const QByteArray &pattern) const
{
    if (m_selectedOffset < 0 || pattern.isEmpty() || m_selectionLength != pattern.size()) {
        return false;
    }

    return m_workingData.mid(m_selectedOffset, pattern.size()) == pattern;
}

void HexDocumentModel::replaceCurrent(bool andAdvance)
{
    try {
        const QByteArray pattern = parseInput(m_findQuery, false, m_searchMode == QStringLiteral("hex"));
        const QByteArray replacement = parseInput(m_replaceQuery, true, m_searchMode == QStringLiteral("hex"));

        if (!selectionMatches(pattern) && !selectMatch(pattern, SearchDirection::Forward)) {
            setStatus(QStringLiteral("No current match to replace."));
            return;
        }

        m_workingData.replace(m_selectedOffset, pattern.size(), replacement);
        m_selectionLength = qMax(1, replacement.size());
        markBufferChanged(QStringLiteral("Replaced the current match."));

        if (andAdvance) {
            selectMatch(pattern, SearchDirection::Forward);
        }
    } catch (const std::runtime_error &error) {
        setError(QString::fromUtf8(error.what()));
    }
}

int HexDocumentModel::replaceBytes(int offset, int length, const QByteArray &replacement, const QString &message)
{
    if (offset < 0 || offset >= m_workingData.size()) {
        return 0;
    }

    const int actualLength = qMax(0, qMin(length, m_workingData.size() - offset));
    m_workingData.replace(offset, actualLength, replacement);
    m_selectedOffset = qMin(offset, qMax(m_workingData.size() - 1, 0));
    m_selectionLength = qMax(1, replacement.size());
    markBufferChanged(message);
    return replacement.size();
}

QString HexDocumentModel::visibleSelectionText() const
{
    if (m_selectedOffset < 0 || m_workingData.isEmpty()) {
        return {};
    }

    QString output;
    const int length = qMin(m_selectionLength, m_workingData.size() - m_selectedOffset);
    output.reserve(length);

    for (int index = 0; index < length; ++index) {
        output += printableCharacter(static_cast<unsigned char>(m_workingData.at(m_selectedOffset + index)));
    }

    return output;
}

void HexDocumentModel::refreshMetadata(const QFileInfo &sourceInfo, const QFileInfo &resolvedInfo)
{
    m_metadata.kindDescription = sourceInfo.suffix().toLower() == QStringLiteral("app")
        ? QStringLiteral("Application bundle executable")
        : QMimeDatabase().mimeTypeForFile(sourceInfo).comment();
    m_metadata.sizeDescription = QLocale().formattedDataSize(m_workingData.size());
    m_metadata.ownerName = resolvedInfo.owner();
    m_metadata.groupName = resolvedInfo.group();
    m_metadata.createdText = resolvedInfo.birthTime().isValid() ? QLocale().toString(resolvedInfo.birthTime(), QLocale::ShortFormat) : QStringLiteral("—");
    m_metadata.modifiedText = resolvedInfo.lastModified().isValid() ? QLocale().toString(resolvedInfo.lastModified(), QLocale::ShortFormat) : QStringLiteral("—");
    emit metadataChanged();
}

void HexDocumentModel::refreshHashes()
{
    m_hashes.md5 = QString::fromLatin1(QCryptographicHash::hash(m_workingData, QCryptographicHash::Md5).toHex());
    m_hashes.sha1 = QString::fromLatin1(QCryptographicHash::hash(m_workingData, QCryptographicHash::Sha1).toHex());
    m_hashes.sha256 = QString::fromLatin1(QCryptographicHash::hash(m_workingData, QCryptographicHash::Sha256).toHex());
    emit hashesChanged();
}

void HexDocumentModel::ensureBase64()
{
    if (m_base64Ready) {
        return;
    }

    m_base64Cache = QString::fromLatin1(m_workingData.toBase64());
    m_base64Ready = true;
    emit base64ReadyChanged();
}

QString HexDocumentModel::formatOffset(int offset) const
{
    const int width = qMax(8, QString::number(qMax(m_workingData.size() - 1, 0), 16).size());
    return QStringLiteral("%1").arg(offset, width, 16, QChar('0')).toUpper();
}

QString HexDocumentModel::hexDump() const
{
    QStringList lines;
    lines.reserve(m_rowCount);

    for (int row = 0; row < m_rowCount; ++row) {
        QStringList hexValues;
        QString asciiText;
        for (int column = 0; column < kBytesPerRow; ++column) {
            const int offset = row * kBytesPerRow + column;
            if (offset < m_workingData.size()) {
                const auto value = static_cast<unsigned char>(m_workingData.at(offset));
                hexValues << hexByte(value);
                asciiText += printableCharacter(value);
            } else {
                hexValues << QStringLiteral("  ");
                asciiText += QLatin1Char(' ');
            }
        }

        lines << QStringLiteral("%1  %2  %3")
                     .arg(formatOffset(row * kBytesPerRow),
                          hexValues.join(QLatin1Char(' ')),
                          asciiText);
    }

    return lines.join(QStringLiteral("\n"));
}

QString HexDocumentModel::decodedText() const
{
    return QString::fromUtf8(m_workingData);
}
