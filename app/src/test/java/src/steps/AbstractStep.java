package src.steps;

import src.steps.impl.GoogleStep;
import src.steps.impl.PDFStep;

public abstract class AbstractStep {
    private

    public static AbstractStep getInstance(String url) {
        switch (url) {
            case "https://www.google.com":
                return new GoogleStep();
            case "https://www.kansaigaidai.ac.jp/asp/img/pdf/82/7a79c35f7ce0704dec63be82440c8182.pdf":
                return new PDFStep();
        }
        return null;
    }

    abstract public void open();
}
