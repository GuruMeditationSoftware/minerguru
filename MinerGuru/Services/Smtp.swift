import Foundation

enum SmtpSecurity: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Plain connection upgraded with STARTTLS, usually port 587.
    case startTLS
    /// TLS from the first byte, usually port 465.
    case tls
    /// No encryption, only for a relay in the own network.
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startTLS: "STARTTLS"
        case .tls: "SSL/TLS"
        case .none: String(localized: "None")
        }
    }

    var defaultPort: Int {
        switch self {
        case .startTLS: 587
        case .tls: 465
        case .none: 25
        }
    }
}

struct SmtpError: LocalizedError, Equatable, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// A plain-text mail, encoded for the DATA phase.
struct SmtpMessage: Equatable, Sendable {
    var from: String
    var to: [String]
    var subject: String
    var body: String
    var date: Date = Date()
    var messageID: String = UUID().uuidString

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss '+0000'"
        return formatter
    }()

    /// RFC 2047 for headers with non-ASCII text.
    static func encodedHeader(_ text: String) -> String {
        guard text.utf8.contains(where: { $0 > 126 || $0 < 32 }) else { return text }
        return "=?UTF-8?B?" + Data(text.utf8).base64EncodedString() + "?="
    }

    /// Headers and a base64 body, lines ending in CRLF, ready to go between DATA and the final dot.
    var encoded: String {
        let domain = from.split(separator: "@").last.map(String.init) ?? "minerguru.local"
        let bodyLines = Data(body.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return [
            "From: \(from)",
            "To: \(to.joined(separator: ", "))",
            "Subject: \(Self.encodedHeader(subject))",
            "Date: \(Self.dateFormat.string(from: date))",
            "Message-ID: <\(messageID)@\(domain)>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
            "",
            bodyLines,
        ].joined(separator: "\r\n")
    }
}

/// The SMTP dialogue without any networking: feed it the server's replies, it says what to send next.
struct SmtpDialogue: Sendable {
    enum Action: Equatable, Sendable {
        case send(String)
        case startTLS
        case done
    }

    private enum Step { case greeting, ehlo, startTLS, ehloAfterTLS, auth, user, password, mailFrom, rcptTo(Int), data, body, quit }

    private let message: SmtpMessage
    private let username: String
    private let password: String
    private let useStartTLS: Bool
    private let clientName: String
    private var step = Step.greeting

    init(message: SmtpMessage, username: String, password: String, useStartTLS: Bool, clientName: String = "minerguru.local") {
        self.message = message
        self.username = username
        self.password = password
        self.useStartTLS = useStartTLS
        self.clientName = clientName
    }

    /// Takes the final line of a reply (`250 OK`) and all its lines, returns the next thing to do.
    mutating func next(code: Int, text: String) throws -> Action {
        switch step {
        case .greeting:
            try expect(code, 220, text)
            step = .ehlo
            return .send("EHLO \(clientName)")
        case .ehlo:
            try expect(code, 250, text)
            if useStartTLS {
                guard text.uppercased().contains("STARTTLS") else {
                    throw SmtpError(message: String(localized: "The mail server does not offer STARTTLS."))
                }
                step = .startTLS
                return .send("STARTTLS")
            }
            return authenticate()
        case .startTLS:
            try expect(code, 220, text)
            step = .ehloAfterTLS
            return .startTLS
        case .ehloAfterTLS:
            try expect(code, 250, text)
            return authenticate()
        case .auth:
            try expect(code, 334, text)
            step = .user
            return .send(Data(username.utf8).base64EncodedString())
        case .user:
            try expect(code, 334, text)
            step = .password
            return .send(Data(password.utf8).base64EncodedString())
        case .password:
            try expect(code, 235, text)
            step = .mailFrom
            return .send("MAIL FROM:<\(message.from)>")
        case .mailFrom:
            try expect(code, 250, text)
            step = .rcptTo(1)
            return .send("RCPT TO:<\(message.to[0])>")
        case .rcptTo(let index):
            try expect(code, 250, text)
            if index < message.to.count {
                step = .rcptTo(index + 1)
                return .send("RCPT TO:<\(message.to[index])>")
            }
            step = .data
            return .send("DATA")
        case .data:
            try expect(code, 354, text)
            step = .body
            return .send(Self.dotStuffed(message.encoded) + "\r\n.")
        case .body:
            try expect(code, 250, text)
            step = .quit
            return .send("QUIT")
        case .quit:
            return .done
        }
    }

    /// The command that follows TLS negotiation.
    var ehlo: String { "EHLO \(clientName)" }

    private mutating func authenticate() -> Action {
        if username.isEmpty {
            step = .mailFrom
            return .send("MAIL FROM:<\(message.from)>")
        }
        step = .auth
        return .send("AUTH LOGIN")
    }

    private func expect(_ code: Int, _ wanted: Int, _ text: String) throws {
        guard code == wanted else { throw SmtpError(message: String(localized: "Mail server: \(text)")) }
    }

    /// Lines that start with a dot get a second one, so they do not end the message.
    static func dotStuffed(_ text: String) -> String {
        text.components(separatedBy: "\r\n").map { $0.hasPrefix(".") ? "." + $0 : $0 }.joined(separator: "\r\n")
    }
}

struct SmtpServer: Equatable, Sendable {
    var host: String
    var port: Int
    var security: SmtpSecurity
    var username: String
    var password: String
}

/// Blocking SMTP over Foundation streams, which unlike Network.framework can start TLS on an open connection.
enum SmtpClient {
    static func send(_ message: SmtpMessage, via server: SmtpServer, timeout: TimeInterval = 20) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try run(message, server, timeout)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func run(_ message: SmtpMessage, _ server: SmtpServer, _ timeout: TimeInterval) throws {
        var input: InputStream?
        var output: OutputStream?
        Stream.getStreamsToHost(withName: server.host, port: server.port, inputStream: &input, outputStream: &output)
        guard let input, let output else { throw SmtpError(message: String(localized: "Mail server not reachable.")) }
        if server.security == .tls { enableTLS(input, output) }
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        let deadline = Date().addingTimeInterval(timeout)
        var dialogue = SmtpDialogue(message: message, username: server.username, password: server.password,
                                    useStartTLS: server.security == .startTLS)
        var pending = Data()
        var reply: (code: Int, text: String)
        while true {
            reply = try readReply(input, buffer: &pending, deadline: deadline)
            switch try dialogue.next(code: reply.code, text: reply.text) {
            case .send(let line):
                try write(line + "\r\n", to: output, deadline: deadline)
            case .startTLS:
                enableTLS(input, output)
                try write(dialogue.ehlo + "\r\n", to: output, deadline: deadline)
            case .done:
                return
            }
        }
    }

    private static func enableTLS(_ input: InputStream, _ output: OutputStream) {
        input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
    }

    /// Reads one reply; lines with `-` after the code continue it.
    private static func readReply(_ input: InputStream, buffer: inout Data, deadline: Date) throws -> (code: Int, text: String) {
        var text = ""
        while true {
            let line = try readLine(input, buffer: &buffer, deadline: deadline)
            text += line + "\n"
            let characters = Array(line)
            guard characters.count >= 3, let code = Int(String(characters[0..<3])) else {
                throw SmtpError(message: String(localized: "Unexpected reply from the mail server."))
            }
            if characters.count == 3 || characters[3] != "-" {
                return (code, text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private static func readLine(_ input: InputStream, buffer: inout Data, deadline: Date) throws -> String {
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            if let end = buffer.firstRange(of: Data([13, 10])) {
                let line = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                return line
            }
            guard Date() < deadline else { throw SmtpError(message: String(localized: "The mail server timed out.")) }
            if input.streamStatus == .error { throw SmtpError(message: input.streamError?.localizedDescription ?? String(localized: "Mail server not reachable.")) }
            if input.hasBytesAvailable {
                let count = input.read(&chunk, maxLength: chunk.count)
                if count < 0 { throw SmtpError(message: input.streamError?.localizedDescription ?? String(localized: "Mail server not reachable.")) }
                if count == 0 { throw SmtpError(message: String(localized: "The mail server closed the connection.")) }
                buffer.append(contentsOf: chunk[0..<count])
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    private static func write(_ text: String, to output: OutputStream, deadline: Date) throws {
        var bytes = Array(text.utf8)[...]
        while !bytes.isEmpty {
            guard Date() < deadline else { throw SmtpError(message: String(localized: "The mail server timed out.")) }
            if output.streamStatus == .error { throw SmtpError(message: output.streamError?.localizedDescription ?? String(localized: "Mail server not reachable.")) }
            if output.hasSpaceAvailable {
                let written = bytes.withUnsafeBufferPointer { output.write($0.baseAddress!, maxLength: $0.count) }
                if written < 0 { throw SmtpError(message: output.streamError?.localizedDescription ?? String(localized: "Mail server not reachable.")) }
                bytes = bytes.dropFirst(written)
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
}
