package src.utils;

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
    private static Configuration config = Configuration.getInstance();

    public static void moveCapture2reference(String fileName) throws IOException {
        Path captureDir = Paths.get(config.get("screenshot.capture.dir"));
        Path referenceDir = Paths.get(config.get("screenshot.reference.dir"));

        Files.move(captureDir.resolve(fileName), referenceDir.resolve(fileName), StandardCopyOption.REPLACE_EXISTING);
    }

    public static void takeScreenshot(String fileName) throws IOException {
        Screenshot screenshot = new AShot()
                .shootingStrategy(ShootingStrategies.viewportPasting(100))
                .takeScreenshot(Selenide.webdriver().object());

        AllureUtils.attachScreenshot("今回取得したキャプチャ", screenshot.getImage());

        Path dir = Paths.get(config.get("screenshot.capture.dir"));
        Files.createDirectories(dir);
        ImageIO.write(screenshot.getImage(), "PNG", dir.resolve(fileName).toFile());
    }

    public static void compareScreenshot(String fileName) throws IOException {
        Path captureDir = Paths.get(config.get("screenshot.capture.dir"));
        Path referenceDir = Paths.get(config.get("screenshot.reference.dir"));

        var captureImage = ImageIO.read(captureDir.resolve(fileName).toFile());
        var referenceImage = ImageIO.read(referenceDir.resolve(fileName).toFile());

        AllureUtils.attachScreenshot("比較対象のキャプチャ", referenceImage);
        AllureUtils.attachScreenshot("比較結果", new ImageDiffer().makeDiff(captureImage, referenceImage).getMarkedImage());
    }
}