package src.utils;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

import javax.imageio.ImageIO;

import io.qameta.allure.Attachment;

public class AllureUtils {

    @Attachment(value = "{0}", type = "image/png")
    public static byte[] attachScreenshot(String name, BufferedImage image) throws IOException {
        try (ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {
            ImageIO.write(image, "PNG", outputStream);
            return outputStream.toByteArray();
        }
    }
}
