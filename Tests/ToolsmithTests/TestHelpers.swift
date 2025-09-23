import XCTest

extension XCTestCase {
  func captureOutput(_ work: () -> Void) -> String {
    let pipe = Pipe()
    let fd = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    work()
    fflush(nil)
    dup2(fd, STDOUT_FILENO)
    pipe.fileHandleForWriting.closeFile()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  }
}
