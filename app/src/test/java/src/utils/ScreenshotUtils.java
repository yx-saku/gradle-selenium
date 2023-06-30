package src.utils;

import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;

import javax.imageio.ImageIO;

import com.codeborne.selenide.Selenide;

import ru.yandex.qatools.ashot.AShot;
import ru.yandex.qatools.ashot.Screenshot;
import ru.yandex.qatools.ashot.comparison.ImageDiffer;
import ru.yandex.qatools.ashot.shooting.ShootingStrategies;

public class ScreenshotUtils {
    public static void moveCapture2reference(String fileName) throws IOException {
        Path captureDir = Paths.get(System.getProperty("screenshot.capture.dir"));
        Path referenceDir = Paths.get(System.getProperty("screenshot.reference.dir"));

        if (Files.exists(captureDir.resolve(fileName))) {
            Files.createDirectories(referenceDir);
            Files.move(captureDir.resolve(fileName), referenceDir.resolve(fileName),
                    StandardCopyOption.REPLACE_EXISTING);
        }
    }

    public static void takeScreenshot(String fileName) throws IOException {
        Screenshot screenshot = new AShot()
                .shootingStrategy(ShootingStrategies.viewportPasting(100))
                .takeScreenshot(Selenide.webdriver().object());

        saveAndAttachImage("取得したキャプチャ", "screenshot.capture.dir", fileName, screenshot.getImage());
    }

    public static void compareScreenshot(String fileName) throws IOException {
        Path referenceDir = Paths.get(System.getProperty("screenshot.reference.dir"));
        if (Files.exists(referenceDir.resolve(fileName))) {
            var referenceImage = ImageIO.read(referenceDir.resolve(fileName).toFile());
            saveAndAttachImage("比較対象のキャプチャ", "screenshot.reference.dir", fileName, referenceImage);

            Path captureDir = Paths.get(System.getProperty("screenshot.capture.dir"));
            var captureImage = ImageIO.read(captureDir.resolve(fileName).toFile());

            var diffImage = new ImageDiffer().makeDiff(captureImage, referenceImage).getMarkedImage();
            saveAndAttachImage("比較結果", "screenshot.diff.dir", fileName, diffImage);
        }
    }

    private static void saveAndAttachImage(String attachName, String dirPathPropertyName, String fileName,
            BufferedImage image) throws IOException {
        AllureUtils.attachScreenshot(attachName, image);

        Path dir = Paths.get(System.getProperty(dirPathPropertyName));
        Files.createDirectories(dir);
        ImageIO.write(image, "PNG", dir.resolve(fileName).toFile());
    }
}