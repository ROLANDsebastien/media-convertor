import XCTest

@testable import Convertor

class ConvertorViewModelTests: XCTestCase {

    var viewModel: ConvertorViewModel!

    override func setUp() {
        super.setUp()
        viewModel = ConvertorViewModel(settings: Settings())
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    func test_add_flac_file() {
        // Given
        let flacURL = URL(fileURLWithPath: "/path/to/test.flac")

        // When
        viewModel.addFile(flacURL)

        // Then
        XCTAssertEqual(viewModel.conversionItems.count, 1)
        XCTAssertEqual(viewModel.conversionItems.first?.sourceURL, flacURL)
        XCTAssertEqual(viewModel.conversionItems.first?.status, .pending)
        XCTAssertEqual(viewModel.conversionItems.first?.outputFormat, .aac)
    }

    func test_add_webm_file() {
        // Given
        let webmURL = URL(fileURLWithPath: "/path/to/test.webm")

        // When
        viewModel.addFile(webmURL)

        // Then
        XCTAssertEqual(viewModel.conversionItems.count, 1)
        XCTAssertEqual(viewModel.conversionItems.first?.sourceURL, webmURL)
        XCTAssertEqual(viewModel.conversionItems.first?.status, .pending)
        XCTAssertEqual(viewModel.conversionItems.first?.mediaType, .video)
        XCTAssertEqual(viewModel.conversionItems.first?.outputFormat, .mp4)
    }

    func test_add_invalid_file() {
        // Given
        let txtURL = URL(fileURLWithPath: "/path/to/test.txt")

        // When
        viewModel.addFile(txtURL)

        // Then
        XCTAssertEqual(viewModel.conversionItems.count, 0)
    }
}
