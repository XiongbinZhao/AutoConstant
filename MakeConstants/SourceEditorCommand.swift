//
//  SourceEditorCommand.swift
//  MakeConstants
//
//  Created by Xiongbin Zhao on 2017-12-25.
//  Copyright © 2017 Xiongbin Zhao. All rights reserved.
//

import Foundation
import XcodeKit

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    let OCStringPattern = "@\"((?:[a-z]|[A-Z]|-|_)*)\""
    let DefineMarcoPattern = "[\\s]*#[\\s]*define[\\s]+(\\S+?)[\\s]+(\\S*)"
    let emptyStringKey = "kEmptyString"
    let objective_c_source_UTI = "public.objective-c-source"
    let c_header_UTI = "public.c-header"
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        
        guard invocation.buffer.contentUTI == objective_c_source_UTI || invocation.buffer.contentUTI == c_header_UTI else {
            completionHandler(nil)
            return
        }
        
        var updatedLineIndexes = [Int]()
        var lineToInsert = -1
        var constantDict = [String: String]()
        var existingConstantsDict = [String: String]()
        for line in 0..<invocation.buffer.lines.count {
            
            guard var lineString = invocation.buffer.lines[line] as? String else { fatalError() }
            if lineString.starts(with: "#import") || lineString.starts(with: "#define") {
                lineToInsert = line + 1
            }
            
            //Parsing defined constant and saved to existingConstantsDict
            let constantsResult = lineString.matchesWith(pattern: DefineMarcoPattern)
            if constantsResult.first != nil {
                self.getDefinedConstants(from: constantsResult, saveTo: &existingConstantsDict)
                continue
            }
            
            //Parsing all the Objective-C string literals
            let results = lineString.matchesWith(pattern: OCStringPattern)
            guard results.first != nil else { continue }
            for i in 0..<results.count where i.isEven() {
                let wholeString = results[i]
                let content = results[i+1]
                let constantKey = content.count == 0 ? emptyStringKey : "k\(content)".replacingOccurrences(of: "-", with: "_")
                
                //Check if there's a existing constant for current string. If so, use it.
                let existingKeysForWholeSring = existingConstantsDict.allKeys(forValue: wholeString)
                if let firstKey = existingKeysForWholeSring.first {
                    lineString = lineString.replacingOccurrences(of: wholeString, with: firstKey)
                } else {
                    //No existing constants for current string.
                    //Only make a new constant if the key is not duplicate
                    if !existingConstantsDict.keys.contains(constantKey) {
                        lineString = lineString.replacingOccurrences(of: wholeString, with: constantKey)
                        constantDict[constantKey] = wholeString;
                    }
                }
            }
            
            invocation.buffer.lines[line] = lineString
            updatedLineIndexes.append(line)
        }
        
        //Create all new Constants
        for (key, value) in constantDict {
            invocation.buffer.lines.insert("#define \(key) \(value)", at: lineToInsert)
        }
        
        
        var lineSelections: [XCSourceTextRange] = updatedLineIndexes.map( {lineIndex in
            let start = lineIndex >= lineToInsert ? lineIndex + constantDict.count : lineIndex
            let startPosition = XCSourceTextPosition(line: start, column: 0)
            let endPosition = XCSourceTextPosition(line: start + 1, column: 0)
            return XCSourceTextRange(start: startPosition, end: endPosition)
        })
        
        if constantDict.count > 0 {
            let constantsTextRange = XCSourceTextRange(start: XCSourceTextPosition(line: lineToInsert, column: 0),
                                                       end: XCSourceTextPosition(line: lineToInsert + constantDict.count, column: 0))
            lineSelections.append(constantsTextRange)
        }
        
        
        
        invocation.buffer.selections.setArray(lineSelections)
        
        completionHandler(nil)
    }
    
    fileprivate func getDefinedConstants(from result:Array<String>, saveTo dict: inout [String: String]) {
        for i in stride(from: 0, to: result.count, by: 3) {
            let key = result[i+1]
            let value = result[i+2]
            if key.count > 0 {
                if !dict.keys.contains(key) {
                    dict[key] = value
                }
            }
        }
    }
}

extension Int {
    fileprivate func isEven() -> Bool {
        return self % 2 == 0
    }
}

extension String {
    fileprivate func matchesWith(pattern: String) -> Array<String> {
        var results = [String]()
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: self.count))
        
        for match in matches {
            for i in 0..<match.numberOfRanges {
                let capturedGroupIndex = match.range(at: i)
                let start = self.index(self.startIndex, offsetBy: capturedGroupIndex.location)
                let end = self.index(self.startIndex, offsetBy: capturedGroupIndex.location + capturedGroupIndex.length)
                let subString = String(self[start..<end])
                results.append(subString)
            }
        }
        
        return results
    }
}

extension Dictionary where Value: Equatable {
    fileprivate func allKeys(forValue val: Value) -> [Key] {
        return self.filter { $1 == val }.map { $0.0 }
    }
}

