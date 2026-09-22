#include <QApplication>
#include <QCommandLineParser>
#include <QDirIterator>
#include <QGraphicsPixmapItem>
#include <QGraphicsScene>
#include <QGraphicsView>
#include <QImageReader>
#include <QKeyEvent>
#include <QMainWindow>
#include <QMessageLogger>
#include <QPixmap>
#include <QRandomGenerator>
#include <QTimer>
#include <QUrl>
#include <QVariantAnimation>
#include <QVector>
#include <algorithm>

namespace {
const QStringList kImageSuffixes = {"jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff"};
}

class PhotoScreenWindow final : public QGraphicsView {
public:
    PhotoScreenWindow(QString folder, int intervalSeconds, bool shuffle)
        : folder_(std::move(folder)), intervalSeconds_(qMax(5, intervalSeconds)), shuffle_(shuffle) {
        scene_ = new QGraphicsScene(this);
        scene_->setBackgroundBrush(Qt::black);
        setScene(scene_);
        setFrameShape(QFrame::NoFrame);
        setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
        setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
        setAlignment(Qt::AlignCenter);
        setFocusPolicy(Qt::StrongFocus);
        connect(&timer_, &QTimer::timeout, this, &PhotoScreenWindow::nextPhoto);
        indexPhotos();
    }

    bool hasPhotos() const { return !photos_.isEmpty(); }

public slots:
    void startSlideshow() {
        if (!hasPhotos()) return;
        showPhoto();
        timer_.start(intervalSeconds_ * 1000);
        setFocus();
    }

protected:
    void resizeEvent(QResizeEvent* event) override {
        QGraphicsView::resizeEvent(event);
        if (item_) layoutPhoto(false);
    }

    void keyPressEvent(QKeyEvent* event) override {
        switch (event->key()) {
        case Qt::Key_Escape:
            close();
            return;
        case Qt::Key_Right:
        case Qt::Key_Space:
            nextPhoto();
            return;
        case Qt::Key_Left:
            previousPhoto();
            return;
        default:
            QGraphicsView::keyPressEvent(event);
        }
    }

private:
    void nextPhoto() {
        if (!hasPhotos()) return;
        index_ = (index_ + 1) % photos_.size();
        showPhoto();
    }

    void previousPhoto() {
        if (!hasPhotos()) return;
        index_ = (index_ - 1 + photos_.size()) % photos_.size();
        showPhoto();
    }

private:
    void indexPhotos() {
        QDirIterator iterator(folder_, QDir::Files, QDirIterator::Subdirectories);
        while (iterator.hasNext()) {
            const QString path = iterator.next();
            const QString suffix = QFileInfo(path).suffix().toLower();
            if (kImageSuffixes.contains(suffix)) photos_.append(path);
        }
        if (shuffle_) {
            for (int i = photos_.size() - 1; i > 0; --i) {
                const int j = QRandomGenerator::global()->bounded(i + 1);
                photos_.swapItemsAt(i, j);
            }
        } else {
            std::sort(photos_.begin(), photos_.end());
        }
    }

    void showPhoto() {
        QImageReader reader(photos_.at(index_));
        reader.setAutoTransform(true);
        const QImage image = reader.read();
        if (image.isNull()) {
            qWarning() << "Unable to read image:" << photos_.at(index_) << reader.errorString();
            nextPhoto();
            return;
        }
        scene_->clear();
        item_ = scene_->addPixmap(QPixmap::fromImage(image));
        item_->setTransformationMode(Qt::SmoothTransformation);
        layoutPhoto(true);
    }

    void layoutPhoto(bool animate) {
        if (!item_ || item_->pixmap().isNull()) return;
        const QSize viewportSize = viewport()->size();
        const QSizeF imageSize = item_->pixmap().size();
        if (viewportSize.width() <= 0 || viewportSize.height() <= 0) return;

        const qreal fitScale = qMin(viewportSize.width() / imageSize.width(),
                                    viewportSize.height() / imageSize.height());
        const qreal fillScale = qMax(viewportSize.width() / imageSize.width(),
                                     viewportSize.height() / imageSize.height());
        const QPointF center(viewportSize.width() / 2.0, viewportSize.height() / 2.0);
        scene_->setSceneRect(0, 0, viewportSize.width(), viewportSize.height());
        item_->setTransformOriginPoint(imageSize.width() / 2.0, imageSize.height() / 2.0);
        item_->setPos(center.x() - imageSize.width() / 2.0, center.y() - imageSize.height() / 2.0);
        item_->setScale(fitScale);

        if (!animate || fillScale <= fitScale + 0.0001) return;
        auto* animation = new QVariantAnimation(this);
        animation->setDuration(qMax(5000, intervalSeconds_ * 1000));
        animation->setStartValue(fitScale);
        animation->setEndValue(fillScale);
        animation->setEasingCurve(QEasingCurve::InOutSine);
        connect(animation, &QVariantAnimation::valueChanged, this, [this](const QVariant& value) {
            if (item_) item_->setScale(value.toReal());
        });
        connect(animation, &QVariantAnimation::finished, animation, &QObject::deleteLater);
        animation->start();
    }

    QString folder_;
    int intervalSeconds_;
    bool shuffle_;
    QStringList photos_;
    int index_ = 0;
    QTimer timer_;
    QGraphicsScene* scene_ = nullptr;
    QGraphicsPixmapItem* item_ = nullptr;
};

int main(int argc, char* argv[]) {
    QApplication application(argc, argv);
    QCoreApplication::setApplicationName("HouseControl PhotoScreen");
    QCoreApplication::setApplicationVersion("0.1.0");

    QCommandLineParser parser;
    parser.setApplicationDescription("HouseControl photo slideshow");
    parser.addHelpOption();
    parser.addVersionOption();
    QCommandLineOption folderOption({"f", "folder"}, "Photo folder", "path");
    QCommandLineOption intervalOption({"i", "interval"}, "Seconds between photos (minimum 5)", "seconds", "60");
    QCommandLineOption shuffleOption({"s", "shuffle"}, "Shuffle photos");
    parser.addOption(folderOption);
    parser.addOption(intervalOption);
    parser.addOption(shuffleOption);
    parser.process(application);

    const QString folder = parser.value(folderOption).isEmpty()
        ? QDir::homePath() + "/Pictures"
        : parser.value(folderOption);
    bool intervalOk = false;
    const int interval = parser.value(intervalOption).toInt(&intervalOk);
    if (!intervalOk || interval < 5) {
        parser.showHelp(2);
    }

    PhotoScreenWindow window(folder, interval, parser.isSet(shuffleOption));
    if (!window.hasPhotos()) {
        qCritical() << "No supported photos found in" << folder;
        return 1;
    }
    window.showFullScreen();
    window.startSlideshow();
    return application.exec();
}
