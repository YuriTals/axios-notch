import XCTest
@testable import AxiosNotch

final class ProcessDirectoryTests: XCTestCase {
    func testProjectNameIsTheFolderName() {
        XCTAssertEqual(ProcessDirectory.projectName(forPath: "/Users/yuri/Documents/Projects/Axios Notch", home: "/Users/yuri"), "Axios Notch")
        XCTAssertEqual(ProcessDirectory.projectName(forPath: "/Users/yuri/code/app/", home: "/Users/yuri"), "app")
    }

    func testHomeAndRootAreNotProjects() {
        XCTAssertNil(ProcessDirectory.projectName(forPath: "/Users/yuri", home: "/Users/yuri"))
        XCTAssertNil(ProcessDirectory.projectName(forPath: "/Users/yuri/", home: "/Users/yuri"))
        XCTAssertNil(ProcessDirectory.projectName(forPath: "/", home: "/Users/yuri"))
        XCTAssertNil(ProcessDirectory.projectName(forPath: "", home: "/Users/yuri"))
    }

    func testReadsTheDirectoryOfARunningProcess() {
        // This test process runs from somewhere real; the lookup must agree with FileManager.
        let cwd = ProcessDirectory.current(pid: getpid())
        XCTAssertNotNil(cwd)
        XCTAssertEqual(cwd.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path)
        XCTAssertNil(ProcessDirectory.current(pid: 0))
    }
}
