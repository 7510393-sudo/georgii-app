import XCTest
@testable import Chronotheca

/// Перенос меток из Google Карт (P512): разбор файлов выгрузки.
final class GoogleMapsImportTests: XCTestCase {

    func testCoordinatesFromLinkWithPinMarker() {
        let c = GoogleMapsImport.coordinates(
            inURL: "https://www.google.com/maps/place/X/@51.5014,-0.1419,17z/data=!3d51.5007!4d-0.1246")
        XCTAssertEqual(c?.0 ?? 0, 51.5007, accuracy: 0.0001)
        XCTAssertEqual(c?.1 ?? 0, -0.1246, accuracy: 0.0001)
    }

    func testCoordinatesFromLinkWithoutPlace() {
        XCTAssertNil(GoogleMapsImport.coordinates(inURL: "https://www.google.com/maps/place/Home"))
    }

    func testSavedPlacesJSON() {
        let json = """
        {"type":"FeatureCollection","features":[
          {"geometry":{"coordinates":[-0.1246,51.5007],"type":"Point"},
           "properties":{"Title":"Big Ben","Comment":"tower"}},
          {"geometry":{"coordinates":[0,0],"type":"Point"},
           "properties":{"Title":"No coordinates"}}
        ]}
        """
        let found = GoogleMapsImport.parse(Data(json.utf8), ext: "json")
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].name, "Big Ben")
        XCTAssertEqual(found[0].latitude ?? 0, 51.5007, accuracy: 0.0001)
        XCTAssertEqual(found[0].longitude ?? 0, -0.1246, accuracy: 0.0001)
        XCTAssertNil(found[1].latitude)
    }

    func testSavedListCSV() {
        let csv = "Title,Note,URL,Comment\nHome,\"a, b\",\"https://www.google.com/maps/place/Home/@51.5,-0.12,17z\",\nLost,,https://www.google.com/maps/place/Lost,\n"
        let found = GoogleMapsImport.parse(Data(csv.utf8), ext: "csv")
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].name, "Home")
        XCTAssertEqual(found[0].note, "a, b")
        XCTAssertEqual(found[0].latitude ?? 0, 51.5, accuracy: 0.0001)
        XCTAssertNil(found[1].latitude)
    }

    func testMyMapsKML() {
        let kml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2"><Document>
          <Placemark><name>Cafe</name><description><![CDATA[<b>nice</b>]]></description>
            <Point><coordinates>-0.1246,51.5007,0</coordinates></Point></Placemark>
        </Document></kml>
        """
        let found = GoogleMapsImport.parse(Data(kml.utf8), ext: "kml")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].name, "Cafe")
        XCTAssertEqual(found[0].note, "nice")
        XCTAssertEqual(found[0].latitude ?? 0, 51.5007, accuracy: 0.0001)
    }
}
