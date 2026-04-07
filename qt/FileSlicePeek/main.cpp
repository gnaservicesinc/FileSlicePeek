#include <QGuiApplication>
#include <QQuickStyle>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "hexdocumentmodel.h"

int main(int argc, char *argv[])
{
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("AJS Tools"));
    app.setApplicationName(QStringLiteral("FileSlicePeek"));

    QQmlApplicationEngine engine;
    HexDocumentModel backend;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule("FileSlicePeek", "Main");

    return QCoreApplication::exec();
}
