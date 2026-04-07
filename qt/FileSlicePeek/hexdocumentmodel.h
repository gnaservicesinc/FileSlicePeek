#pragma once

#include <QObject>
#include <QByteArray>
#include <QFileInfo>
#include <QStringList>
#include <QUrl>

class HexDocumentModel final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasFile READ hasFile NOTIFY fileChanged)
    Q_PROPERTY(bool dirty READ dirty NOTIFY dirtyChanged)
    Q_PROPERTY(bool base64Ready READ base64Ready NOTIFY base64ReadyChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString displayName READ displayName NOTIFY fileChanged)
    Q_PROPERTY(QString visiblePath READ visiblePath NOTIFY fileChanged)
    Q_PROPERTY(QString kindDescription READ kindDescription NOTIFY metadataChanged)
    Q_PROPERTY(QString sizeDescription READ sizeDescription NOTIFY metadataChanged)
    Q_PROPERTY(QString ownerName READ ownerName NOTIFY metadataChanged)
    Q_PROPERTY(QString groupName READ groupName NOTIFY metadataChanged)
    Q_PROPERTY(QString createdText READ createdText NOTIFY metadataChanged)
    Q_PROPERTY(QString modifiedText READ modifiedText NOTIFY metadataChanged)
    Q_PROPERTY(QString md5Hash READ md5Hash NOTIFY hashesChanged)
    Q_PROPERTY(QString sha1Hash READ sha1Hash NOTIFY hashesChanged)
    Q_PROPERTY(QString sha256Hash READ sha256Hash NOTIFY hashesChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorChanged)
    Q_PROPERTY(QString findQuery READ findQuery WRITE setFindQuery NOTIFY searchInputsChanged)
    Q_PROPERTY(QString replaceQuery READ replaceQuery WRITE setReplaceQuery NOTIFY searchInputsChanged)
    Q_PROPERTY(QString jumpQuery READ jumpQuery WRITE setJumpQuery NOTIFY selectionChanged)
    Q_PROPERTY(QString searchMode READ searchMode WRITE setSearchMode NOTIFY searchInputsChanged)
    Q_PROPERTY(QString selectedHexText READ selectedHexText NOTIFY selectionChanged)
    Q_PROPERTY(QString selectedTextText READ selectedTextText NOTIFY selectionChanged)
    Q_PROPERTY(int rowCount READ rowCount NOTIFY bufferChanged)
    Q_PROPERTY(int dataCount READ dataCount NOTIFY bufferChanged)
    Q_PROPERTY(int selectedOffset READ selectedOffset NOTIFY selectionChanged)
    Q_PROPERTY(int selectionLength READ selectionLength WRITE setSelectionLength NOTIFY selectionChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    explicit HexDocumentModel(QObject *parent = nullptr);

    bool hasFile() const;
    bool dirty() const;
    bool base64Ready() const;
    bool loading() const;

    QString displayName() const;
    QString visiblePath() const;
    QString kindDescription() const;
    QString sizeDescription() const;
    QString ownerName() const;
    QString groupName() const;
    QString createdText() const;
    QString modifiedText() const;

    QString md5Hash() const;
    QString sha1Hash() const;
    QString sha256Hash() const;

    QString statusText() const;
    QString errorMessage() const;

    QString findQuery() const;
    QString replaceQuery() const;
    QString jumpQuery() const;
    QString searchMode() const;
    QString selectedHexText() const;
    QString selectedTextText() const;

    int rowCount() const;
    int dataCount() const;
    int selectedOffset() const;
    int selectionLength() const;
    int revision() const;

    Q_INVOKABLE void openFile(const QUrl &fileUrl);
    Q_INVOKABLE void save();
    Q_INVOKABLE void revert();
    Q_INVOKABLE void moveSelection();
    Q_INVOKABLE void selectOffset(int offset);
    Q_INVOKABLE void applyHexEdit(const QString &value);
    Q_INVOKABLE void applyTextEdit(const QString &value);
    Q_INVOKABLE int replaceHexInput(const QString &value, int offset, int length = 1);
    Q_INVOKABLE int replaceTextInput(const QString &value, int offset, int length = 1);
    Q_INVOKABLE void findNext();
    Q_INVOKABLE void findPrevious();
    Q_INVOKABLE void replaceOne();
    Q_INVOKABLE void replaceOneAndFind();
    Q_INVOKABLE void replaceAll();
    Q_INVOKABLE void exportHex(const QUrl &destinationUrl);
    Q_INVOKABLE void exportText(const QUrl &destinationUrl);
    Q_INVOKABLE void exportBase64(const QUrl &destinationUrl);
    Q_INVOKABLE void copyText(const QString &value);
    Q_INVOKABLE void copySelection(const QString &mode);
    Q_INVOKABLE void copyBase64();
    Q_INVOKABLE void clearError();

    Q_INVOKABLE QString addressForRow(int row) const;
    Q_INVOKABLE bool cellExists(int row, int column) const;
    Q_INVOKABLE QString hexValueAt(int row, int column) const;
    Q_INVOKABLE QString asciiValueAt(int row, int column) const;
    Q_INVOKABLE bool isOffsetSelected(int offset) const;

    void setFindQuery(const QString &value);
    void setReplaceQuery(const QString &value);
    void setJumpQuery(const QString &value);
    void setSearchMode(const QString &value);
    void setSelectionLength(int value);

signals:
    void fileChanged();
    void dirtyChanged();
    void base64ReadyChanged();
    void loadingChanged();
    void metadataChanged();
    void hashesChanged();
    void statusChanged();
    void errorChanged();
    void searchInputsChanged();
    void bufferChanged();
    void selectionChanged();
    void revisionChanged();

private:
    enum class SearchDirection {
        Forward,
        Backward
    };

    struct Metadata {
        QString kindDescription = "No file loaded";
        QString sizeDescription = QStringLiteral("—");
        QString ownerName = QStringLiteral("—");
        QString groupName = QStringLiteral("—");
        QString createdText = QStringLiteral("—");
        QString modifiedText = QStringLiteral("—");
    };

    struct Hashes {
        QString md5 = QStringLiteral("—");
        QString sha1 = QStringLiteral("—");
        QString sha256 = QStringLiteral("—");
    };

    QString resolveInspectablePath(const QUrl &fileUrl) const;
    QByteArray parseInput(const QString &value, bool allowEmpty, bool useHexMode) const;
    int parseOffset(const QString &value) const;
    void setError(const QString &message);
    void setStatus(const QString &message);
    void markBufferChanged(const QString &message);
    void normalizeSelection();
    bool selectMatch(const QByteArray &pattern, SearchDirection direction);
    bool selectionMatches(const QByteArray &pattern) const;
    void replaceCurrent(bool andAdvance);
    int replaceBytes(int offset, int length, const QByteArray &replacement, const QString &message);
    QString visibleSelectionText() const;
    void refreshMetadata(const QFileInfo &sourceInfo, const QFileInfo &resolvedInfo);
    void refreshHashes();
    void ensureBase64();
    QString formatOffset(int offset) const;
    QString hexDump() const;
    QString decodedText() const;

    static constexpr int kBytesPerRow = 16;

    bool m_hasFile = false;
    bool m_dirty = false;
    bool m_base64Ready = false;
    bool m_loading = false;
    int m_rowCount = 0;
    int m_selectedOffset = -1;
    int m_selectionLength = 1;
    int m_revision = 0;

    QString m_displayName = QStringLiteral("FileSlicePeek");
    QString m_visiblePath;
    QString m_statusText = QStringLiteral("Drop a file or choose one to begin.");
    QString m_errorMessage;
    QString m_findQuery;
    QString m_replaceQuery;
    QString m_jumpQuery = QStringLiteral("0x0");
    QString m_searchMode = QStringLiteral("hex");

    Metadata m_metadata;
    Hashes m_hashes;
    QByteArray m_originalData;
    QByteArray m_workingData;
    QString m_base64Cache;
    QUrl m_sourceUrl;
};
