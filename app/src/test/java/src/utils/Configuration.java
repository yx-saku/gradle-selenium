package src.utils;

import java.util.Optional;
import java.util.ResourceBundle;

public class Configuration {
    private static ResourceBundle rb = ResourceBundle.getBundle("config");

    private Configuration() {
    }

    public static Configuration getInstance() {
        return new Configuration();
    }

    public String get(String key) {
        return rb.getString(key);
    }

    public String get(String key, String defaultValue) {
        return Optional.ofNullable(this.get(key)).orElse(defaultValue);
    }
}