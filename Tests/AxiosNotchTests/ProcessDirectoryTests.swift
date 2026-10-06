import XCTest
@testable import AxiosNotch

final class ProcessDirectoryTests: XCTestCase {
    func testProjectNameIsTheFolderName() {
        XCTAssertEqual(ProcessDirectory.projectName(forPath: "/Users/dev/Documents/Projects/Axios Notch", home: "/Users/dev"), "Axios Notch")
        XCTAssertEqual(ProcessDirectory.projectName(forPath: "/Users/dev/code/app/", home: "/Users/dev"), "app")
    }

    func testHomeAndRootAreNotProjects() {
        XCTAssertNil(ProcessDirectory.projectName(forPath: "/Users/dev", home: "/Users/dev"))
        XCTAssertNil(ProcessDirectory.projectName(forPath: "/Users/dev/", home: "/Users/dev"))
        XCTAssertNil(ProcessDirectory.projectName(forPath: "/", home: "/Users/dev"))
        XCTAssertNil(ProcessDirectory.projectName(forPath: "", home: "/Users/dev"))
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
