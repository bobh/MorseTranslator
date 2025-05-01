//
//  MorseTranslatorUITests.swift
//  MorseTranslator
//
//  Created by bobh on 5/1/25.
//


//  MorseTranslatorUITests.swift
//  MorseTranslatorUITests
//
//  Created by bobh on 5/1/25.
//

import XCTest

class MorseTranslatorUITests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testContentViewElements() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Verify title
        XCTAssertTrue(app.staticTexts["Morse Translator"].exists)
        
        // Verify buttons
        let startButton = app.buttons["Start Listening"]
        XCTAssertTrue(startButton.exists)
        
        let changeModeButton = app.buttons["Change Mode"]
        XCTAssertTrue(changeModeButton.exists)
        
        // Verify slider
        XCTAssertTrue(app.sliders.element.exists)
        
        // Verify status indicators
        XCTAssertTrue(app.staticTexts["Listening"].exists)
        XCTAssertTrue(app.staticTexts["Playing Morse"].exists)
    }
    
    func testModeSwitching() throws {
        let app = XCUIApplication()
        app.launch()
        
        let modeText = app.staticTexts["Word Mode"]
        XCTAssertTrue(modeText.exists)
        
        app.buttons["Change Mode"].tap()
        XCTAssertTrue(app.staticTexts["Character Mode"].exists)
        
        app.buttons["Change Mode"].tap()
        XCTAssertTrue(app.staticTexts["Word Mode"].exists)
    }
    
    func testStartStopTranscription() throws {
        let app = XCUIApplication()
        app.launch()
        
        let startButton = app.buttons["Start Listening"]
        XCTAssertTrue(startButton.exists)
        
        startButton.tap()
        let stopButton = app.buttons["Stop Listening"]
        XCTAssertTrue(stopButton.exists)
        
        stopButton.tap()
        XCTAssertTrue(startButton.exists)
    }
    
    func testWPMSlider() throws {
        let app = XCUIApplication()
        app.launch()
        
        let wpmText = app.staticTexts["Speed: 15 WPM"]
        XCTAssertTrue(wpmText.exists)
        
        let slider = app.sliders.element
        slider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(app.staticTexts.matching(identifier: "Speed: 17 WPM").element.exists || app.staticTexts.matching(identifier: "Speed: 18 WPM").element.exists)
    }
}
