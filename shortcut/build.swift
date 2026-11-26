// Writes shortcut/Deskwalk.shortcut, the iPhone Shortcut that logs every saved session
// to Apple Health, and signs it so an iPhone can import it. macOS only (`shortcuts sign`).
// Run: swift shortcut/build.swift
//
// A Shortcut is a property list of actions. Action and parameter names come from
// iOS exports (viticci/shortcuts-playground-plugin) and Cherri's action catalogue.
import Foundation

func output(_ uuid: String, _ name: String) -> [String: Any] {
    ["Type": "ActionOutput", "OutputUUID": uuid, "OutputName": name]
}

func attachment(_ value: [String: Any]) -> [String: Any] {
    ["Value": value, "WFSerializationType": "WFTextTokenAttachment"]
}

let repeatItem: [String: Any] = ["Type": "Variable", "VariableName": "Repeat Item"]

func action(_ id: String, _ params: [String: Any]) -> [String: Any] {
    ["WFWorkflowActionIdentifier": "is.workflow.actions.\(id)", "WFWorkflowActionParameters": params]
}

func value(_ key: String, uuid: String) -> [String: Any] {
    action("getvalueforkey", [
        "UUID": uuid, "CustomOutputName": key, "WFDictionaryKey": key,
        "WFInput": attachment(output("DICT", "Dictionary")),
    ])
}

func date(_ key: String, uuid: String) -> [String: Any] {
    action("detect.date", ["UUID": uuid, "CustomOutputName": "\(key) date", "WFInput": attachment(output(key.uppercased(), key))])
}

func log(_ type: String, magnitude: [String: Any], unit: String) -> [String: Any] {
    action("health.quantity.log", [
        "WFQuantitySampleType": type,
        "WFQuantitySampleQuantity": ["Value": ["Magnitude": magnitude, "Unit": unit], "WFSerializationType": "WFQuantityFieldValue"],
        "WFQuantitySampleDate": attachment(output("STARTDATE", "start date")),
        "WFSampleEndDate": attachment(output("ENDDATE", "end date")),
    ])
}

let actions: [[String: Any]] = [
    // Sessions saved by the Mac app in iCloud Drive/Shortcuts/Deskwalk.
    action("documentpicker.open", ["UUID": "FOLDER", "WFGetFilePath": "Deskwalk/", "WFShowFilePicker": false, "WFFileErrorIfNotFound": false]),
    action("file.getfoldercontents", ["UUID": "FILES", "WFFolder": attachment(output("FOLDER", "File"))]),
    action("repeat.each", ["GroupingIdentifier": "EACH", "WFControlFlowMode": 0, "WFInput": attachment(output("FILES", "Contents of Folder"))]),
    action("detect.dictionary", ["UUID": "DICT", "WFInput": attachment(repeatItem)]),
    value("start", uuid: "START"),
    value("end", uuid: "END"),
    value("steps", uuid: "STEPS"),
    value("distanceKm", uuid: "DIST"),
    date("start", uuid: "STARTDATE"),
    date("end", uuid: "ENDDATE"),
    log("Step Count", magnitude: output("STEPS", "steps"), unit: "count"),
    log("Walking + Running Distance", magnitude: output("DIST", "distanceKm"), unit: "km"),
    action("file.delete", ["WFInput": attachment(repeatItem), "WFDeleteFileConfirmDeletion": false, "WFDeleteImmediatelyDelete": true]),
    action("repeat.each", ["GroupingIdentifier": "EACH", "WFControlFlowMode": 2]),
]

let shortcut: [String: Any] = [
    "WFWorkflowClientVersion": "2605.0.5",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": ["WFWorkflowIconStartColor": 255, "WFWorkflowIconGlyphNumber": 61440],
    "WFWorkflowTypes": [String](),
    "WFWorkflowInputContentItemClasses": [String](),
    "WFWorkflowActions": actions,
]

let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let unsigned = dir.appendingPathComponent("Deskwalk-unsigned.shortcut")
try PropertyListSerialization.data(fromPropertyList: shortcut, format: .binary, options: 0).write(to: unsigned)
let sign = Process()
sign.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
sign.arguments = ["sign", "--mode", "anyone", "--input", unsigned.path, "--output", dir.appendingPathComponent("Deskwalk.shortcut").path]
try sign.run()
sign.waitUntilExit()
try FileManager.default.removeItem(at: unsigned)
guard sign.terminationStatus == 0 else { fatalError("shortcuts sign failed") }
print("shortcut/Deskwalk.shortcut written and signed")
