package src.utils;

import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;

import javax.imageio.ImageIO;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.opentest4j.AssertionFailedError;

import com.codeborne.selenide.Configuration;
import com.codeborne.selenide.Selenide;

import ru.yandex.qatools.ashot.AShot;
import ru.yandex.qatools.ashot.comparison.ImageDiffer;
import ru.yandex.qatools.ashot.shooting.ShootingStrategies;

public class ScreenshotUtils {
    public static String getFileName() {
        return Configuration.browser + ".png";
    }

    /**
     * captureフォルダにあるスクリーンショットをreferenceフォルダに移動する
     * 
     * @throws IOException
     */
    public static void moveCapture2reference() throws IOException {
        var fileName = getFileName();

        var captureDir = Paths.get(System.getProperty("screenshot.capture.dir"));
        var referenceDir = Paths.get(System.getProperty("screenshot.reference.dir"));

        if (Files.exists(captureDir.resolve(fileName))) {
            Files.createDirectories(referenceDir);
            Files.move(captureDir.resolve(fileName), referenceDir.resolve(fileName),
                    StandardCopyOption.REPLACE_EXISTING);
        }
    }

    /**
     * 現在表示しているページのフルスクリーンショットを取得し、captureフォルダに保存する。
     * 
     * @throws IOException
     */
    public static String takeScreenshot() throws IOException {
        var fileName = getFileName();
        var screenshot = new AShot()
                .shootingStrategy(ShootingStrategies.viewportPasting(100))
                .takeScreenshot(Selenide.webdriver().object());

        saveAndAttachImage("取得したキャプチャ", "screenshot.capture.dir", fileName, screenshot.getImage());

        return fileName;
    }

    /**
     * PDFの各ページのスクリーンショットを取得し、captureフォルダに保存する。
     * 取得したスクリーンショットのファイル名は下記の形式。
     * {fileName}-{ページ番号(1始まり)}.png
     * 
     * @param pdfFilePath PDFファイル
     * @return
     * @throws IOException
     */
    public static ArrayList<String> takePdfScreenshot(Path pdfFilePath) throws IOException {
        var fileNames = new ArrayList<String>();
        var pdfFileName = pdfFilePath.getFileName();
        try (var document = PDDocument.load(pdfFilePath.toFile())) {
            var renderer = new PDFRenderer(document);
            for (var i = 0; i < document.getNumberOfPages(); i++) {
                var bufferedImage = renderer.renderImage(i);

                var attachName = String.format("%s %dページ", pdfFileName, i + 1);
                var fileName = String.format("%s-%s-%d.png", Configuration.browser, pdfFileName, i + 1);
                saveAndAttachImage(attachName, "screenshot.capture.dir", fileName, bufferedImage);

                fileNames.add(fileName);
            }
        }

        return fileNames;
    }

    /**
     * captureフォルダとreferenceフォルダにある同名のスクリーンショットを比較する。
     * 
     * @throws IOException
     */
    public static boolean compareScreenshot(String fileName) throws IOException {
        var referenceDir = Paths.get(System.getProperty("screenshot.reference.dir"));
        if (Files.exists(referenceDir.resolve(fileName))) {
            var referenceImage = ImageIO.read(referenceDir.resolve(fileName).toFile());
            saveAndAttachImage("比較対象のキャプチャ", "screenshot.reference.dir", fileName, referenceImage);

            var captureDir = Paths.get(System.getProperty("screenshot.capture.dir"));
            var captureImage = ImageIO.read(captureDir.resolve(fileName).toFile());

            var differ = new ImageDiffer().makeDiff(captureImage, referenceImage);
            var diffImage = differ.getMarkedImage();
            saveAndAttachImage("比較結果", "screenshot.diff.dir", fileName, diffImage);

            if (differ.hasDiff()) {
                new AssertionFailedError("差異を検出しました。ファイル名：" + fileName);
            }

            return !differ.hasDiff();
        }

        return true;
    }

    /**
     * Allureレポートにアタッチしつつ画像をファイルに保存する。
     * 
     * @param attachName          アタッチ名
     * @param dirPathPropertyName 保存先のフォルダパスを示すプロパティ名
     * @param fileName            保存するファイル名
     * @param image               画像
     * @throws IOException
     */
    private static void saveAndAttachImage(String attachName, String dirPathPropertyName, String fileName,
            BufferedImage image) throws IOException {
        AllureUtils.attachScreenshot(attachName, image);

        Path dir = Paths.get(System.getProperty(dirPathPropertyName));
        Files.createDirectories(dir);
        ImageIO.write(image, "PNG", dir.resolve(fileName).toFile());
    }
}