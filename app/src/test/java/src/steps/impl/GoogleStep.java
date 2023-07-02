package src.steps.impl;

import static com.codeborne.selenide.Selenide.$;

import com.codeborne.selenide.Configuration;
import com.codeborne.selenide.Selenide;

import src.steps.AbstractStep;

public class GoogleStep extends AbstractStep {

    @Override
    public void open() {
        Selenide.open("https://www.google.com");

        $("[name=q]")
                .setValue("Hello, world!!!!!!! " + Configuration.browser + " "
                        + System.getProperty("selenide.browser"))
                .pressEnter();
    }

}
