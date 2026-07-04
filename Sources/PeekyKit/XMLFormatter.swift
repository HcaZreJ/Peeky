import Foundation

enum XMLFormatter {
    static func prettyXML(_ text: String) throws -> String {
        let document = try XMLDocument(xmlString: text, options: [])
        let data = document.xmlData(options: [.nodePrettyPrint])
        return String(data: data, encoding: .utf8) ?? text
    }

    static func prettyPropertyList(_ text: String) throws -> String {
        let data = Data(text.utf8)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        let xmlData = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        let xml = String(data: xmlData, encoding: .utf8) ?? text
        return try prettyXML(xml)
    }
}
