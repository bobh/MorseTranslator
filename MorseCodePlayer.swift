//  MorseCodePlayer.swift
//  MorseTranslator
//
//  Created by bobh on 4/17/25.
//

import Foundation
import AVFoundation
import os.log

var timerTask: Task<Void, Never>?

@MainActor
class MorseCodePlayer: ObservableObject {
    private let sineFrequency: Float = 800.0
    private let logger = Logger(subsystem: "com.yourapp.speechtomorse", category: "morse")
    private let audioEngine = AVAudioEngine()
    private let audioPlayerNode = AVAudioPlayerNode()
    private let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let safeBuffer: SafeCircularBuffer<String> // Added for dependency injection
    
    private var isProcessingQueue = false
    @Published var isPlaying = false
    @Published var currentWord = ""
    
    private var mode: MorseMode = .word
    var outWord: String = ""
    var safeBufferEmpty: Bool = false
    
    private var dotDuration: Double = 0.1
    private var dashDuration: Double { return dotDuration * 3 }
    private var elementSpacing: Double { return dotDuration }
    private var letterSpacing: Double { return dotDuration * 3 }
    private var wordSpacing: Double { return dotDuration * 7 }
    
    private let morseCodeDict: [Character: String] = [
        "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".",
        "f": "..-.", "g": "--.", "h": "....", "i": "..", "j": ".---",
        "k": "-.-", "l": ".-..", "m": "--", "n": "-.", "o": "---",
        "p": ".--.", "q": "--.-", "r": ".-.", "s": "...", "t": "-",
        "u": "..-", "v": "...-", "w": ".--", "x": "-..-", "y": "-.--",
        "z": "--..", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        "0": "-----", ".": ".-.-.-", ",": "--..--", "?": "..--..",
        "'": ".----.", "!": "-.-.--", "/": "-..-.", "(": "-.--.",
        ")": "-.--.-", "&": ".-...", ":": "---...", ";": "-.-.-.",
        "=": "-...-", "+": ".-.-.", "-": "-....-", "_": "..--.-",
        "\"": ".-..-.", "$": "...-..-", "@": ".--.-.", "#": "....-.-."
    ]
    
    private let digitWords: [String: Character] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"
    ]
    
    private let specialCharacterMap: [String: Character] = [
        "period": ".", "comma": ",", "question mark": "?", "exclamation mark": "!",
        "slash": "/", "at sign": "@", "colon": ":", "semicolon": ";",
        "equals": "=", "plus": "+", "minus": "-", "underscore": "_",
        "quote": "\"", "dollar": "$"
    ]
    
    private let validLetters: Set<String> = Set("abcdefghijklmnopqrstuvwxyz".map { String($0) })
    
    init(safeBuffer: SafeCircularBuffer<String>) {
        self.safeBuffer = safeBuffer
        setupAudioEngine()
        Task {
            startAsyncTimer(interval: dotDuration) {
                await self.processMorseOutput()
            }
        }
    }
    
    deinit {
        stopAsyncTimer()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(audioPlayerNode)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        do {
            try audioEngine.start()
            logger.debug("Audio engine started successfully")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    func setMode(_ newMode: MorseMode) {
        mode = newMode
    }
    
    func setWPM(_ wpm: Int) {
        dotDuration = 60.0 / (50.0 * Double(wpm))
    }
    
    func addWordToQueue(_ word: String) {
        Task {
            if let overwritten = await safeBuffer.push(word) {
                logger.warning("Overwrote word: \(overwritten)")
            }
            logger.debug("Inputting word: '\(word)'")
        }
        if !isProcessingQueue {
            processQueue()
        }
    }
    
    private func processMorseOutput() async {
        safeBufferEmpty = await safeBuffer.isEmpty
        if !safeBufferEmpty {
            if let word = await safeBuffer.pop() {
                outWord = word
            } else {
                outWord = ""
            }
        } else {
            outWord = ""
        }
        logger.debug("Outputting word: '\(self.outWord)'")
    }
    
    private func processQueue() {
        guard !isProcessingQueue, !safeBufferEmpty else {
            logger.debug("Queue empty or processing, skipping")
            return
        }
        
        logger.debug("Processing word: '\(self.outWord)'")
        isProcessingQueue = true
        
        switch mode {
        case .word:
            playMorseForWord(outWord) {
                self.isProcessingQueue = false
                self.processQueue()
            }
        case .character:
            playMorseForCharacter(outWord) {
                self.isProcessingQueue = false
                self.processQueue()
            }
        }
    }
    
    private func playMorseForCharacter(_ word: String, completion: @escaping () -> Void) {
        currentWord = word
        
        let processedChar: Character
        let lowerWord = word.lowercased()
        
        if let specialChar = specialCharacterMap[lowerWord] {
            processedChar = specialChar
            logger.debug("Recognized special character '\(lowerWord)' as '\(specialChar)'")
        } else if lowerWord.count == 1, let firstChar = lowerWord.first, morseCodeDict.keys.contains(firstChar) {
            processedChar = firstChar
            logger.debug("Using single character: '\(processedChar)'")
        } else if let digitChar = digitWords[lowerWord] {
            processedChar = digitChar
            logger.debug("Recognized digit word '\(lowerWord)' as '\(digitChar)'")
        } else {
            processedChar = "#"
            logger.debug("Unrecognized word '\(lowerWord)' in character mode, using '#'")
        }
        
        var playCommands: [(duration: Double, isOn: Bool)] = []
        let lowerChar = processedChar
        
        if let morseChar = morseCodeDict[lowerChar] {
            logger.debug("Playing Morse code for '\(processedChar)': \(morseChar)")
            for (elementIndex, element) in morseChar.enumerated() {
                if element == "." {
                    playCommands.append((dotDuration, true))
                } else if element == "-" {
                    playCommands.append((dashDuration, true))
                }
                if elementIndex < morseChar.count - 1 {
                    playCommands.append((elementSpacing, false))
                }
            }
        } else {
            logger.debug("No Morse code found for character: '\(processedChar)'")
        }
        
        playCommands.append((wordSpacing, false))
        
        logger.debug("Total play commands: \(playCommands.count)")
        
        if playCommands.count > 1 {
            playSequence(playCommands) {
                self.isProcessingQueue = false
                completion()
            }
        } else {
            logger.debug("No valid Morse code to play for: \(word)")
            self.isProcessingQueue = false
            completion()
        }
    }
    
    func playMorseForWord(_ word: String, completion: @escaping () -> Void) {
        currentWord = word
        
        let lowerWord = word.lowercased()
        var playCommands: [(duration: Double, isOn: Bool)] = []
        
        let charsToEncode: [Character]
        if let digitChar = digitWords[lowerWord] {
            charsToEncode = [digitChar]
            logger.debug("Encoding digit word '\(lowerWord)' as '\(digitChar)'")
        } else if validLetters.contains(lowerWord) {
            charsToEncode = [Character(lowerWord)]
            logger.debug("Encoding single letter '\(lowerWord)'")
        } else {
            charsToEncode = lowerWord.map { morseCodeDict.keys.contains($0) ? $0 : "#" }
            logger.debug("Encoding word '\(lowerWord)' as characters: \(charsToEncode)")
        }
        
        for (index, char) in charsToEncode.enumerated() {
            if let morseChar = morseCodeDict[char] {
                for (elementIndex, element) in morseChar.enumerated() {
                    if element == "." {
                        playCommands.append((dotDuration, true))
                    } else if element == "-" {
                        playCommands.append((dashDuration, true))
                    }
                    if elementIndex < morseChar.count - 1 {
                        playCommands.append((elementSpacing, false))
                    }
                }
                if index < charsToEncode.count - 1 {
                    playCommands.append((letterSpacing, false))
                }
            }
        }
        
        playCommands.append((wordSpacing, false))
        
        playSequence(playCommands) {
            self.isProcessingQueue = false
            completion()
        }
    }
    
    private func playSequence(_ commands: [(duration: Double, isOn: Bool)], completion: @escaping () -> Void) {
        guard !commands.isEmpty else {
            completion()
            return
        }
        
        var remainingCommands = commands
        let command = remainingCommands.removeFirst()
        
        if command.isOn {
            playTone(duration: command.duration) {
                self.isPlaying = false
                self.playSequence(remainingCommands, completion: completion)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + command.duration) {
                self.playSequence(remainingCommands, completion: completion)
            }
        }
    }
    
    private func playTone(duration: Double, completion: @escaping () -> Void) {
        let sampleRate: Float = 44100.0
        let totalSamples = UInt32(duration * Double(sampleRate))
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: totalSamples) else {
            logger.error("Could not create buffer")
            completion()
            return
        }
        
        buffer.frameLength = totalSamples
        
        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(buffer.format.channelCount))
        
        for frame in 0..<Int(totalSamples) {
            let value = sinf(2.0 * .pi * self.sineFrequency * Float(frame) / sampleRate)
            for channel in 0..<Int(buffer.format.channelCount) {
                channels[channel][frame] = Float(value) * 0.8
            }
        }
        
        isPlaying = true
        
        logger.debug("Playing tone with duration: \(duration)")
        
        audioPlayerNode.scheduleBuffer(buffer) {
            self.isPlaying = false
            completion()
        }
        
        if !audioPlayerNode.isPlaying {
            audioPlayerNode.play()
        }
    }
}

func startAsyncTimer(interval: TimeInterval, task: @escaping () async -> Void) {
    timerTask = Task {
        while !Task.isCancelled {
            let startTime = Date()
            await task()
            let elapsedTime = Date().timeIntervalSince(startTime)
            let remainingTime = max(0, interval - elapsedTime)
            try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
        }
    }
}

func stopAsyncTimer() {
    timerTask?.cancel()
    timerTask = nil
    logger.info("Timer stopped")
}

/*
Recommendations for future improvements:
1. Add UI to display buffer count (e.g., "Buffer: \(await safeBuffer.count)/130").
*/
