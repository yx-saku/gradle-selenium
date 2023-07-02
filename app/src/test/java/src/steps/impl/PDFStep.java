package src.steps.impl;

import com.codeborne.selenide.Selenide;

import src.steps.AbstractStep;

public class PDFStep extends AbstractStep {
    @Override
    public void open() {
        Selenide.open("https://www.kansaigaidai.ac.jp/asp/img/pdf/82/7a79c35f7ce0704dec63be82440c8182.pdf");
    }
}
