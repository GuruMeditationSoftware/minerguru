#!/usr/bin/env python3
"""Local fake mail server for testing MinerGuru's mail alerts without sending real mail.

Accepts any login on plain SMTP and prints what it gets, with the body decoded:

    python3 MockMiners/mock_smtp.py [--host 0.0.0.0] [--port 2525]

In the app: security "None", server = this machine, port 2525.
"""
import argparse
import base64
import email
import email.header
import socketserver


class Handler(socketserver.StreamRequestHandler):
    def reply(self, line):
        self.wfile.write(line.encode() + b"\r\n")

    def handle(self):
        self.reply("220 mock smtp")
        data = None
        while True:
            line = self.rfile.readline()
            if not line:
                return
            text = line.decode(errors="replace").rstrip("\r\n")
            if data is not None:
                if text == ".":
                    self.show(data)
                    data = None
                    self.reply("250 queued")
                else:
                    data.append(text[1:] if text.startswith("..") else text)
                continue
            command = text.upper()
            if command.startswith("EHLO"):
                self.wfile.write(b"250-mock\r\n250 AUTH LOGIN\r\n")
            elif command.startswith("AUTH"):
                self.reply("334 VXNlcm5hbWU6")
                self.rfile.readline()
                self.reply("334 UGFzc3dvcmQ6")
                self.rfile.readline()
                self.reply("235 ok")
            elif command == "DATA":
                data = []
                self.reply("354 go")
            elif command == "QUIT":
                self.reply("221 bye")
                return
            else:
                print(">", text, flush=True)
                self.reply("250 ok")

    def show(self, lines):
        message = email.message_from_string("\n".join(lines))
        subject = str(email.header.make_header(email.header.decode_header(message["Subject"])))
        body = base64.b64decode("".join(message.get_payload().split())).decode()
        print(f"--- Mail to {message['To']}\nSubject: {subject}\n{body}\n---", flush=True)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=2525)
    args = parser.parse_args()
    print(f"Fake SMTP on {args.host}:{args.port}", flush=True)
    Server((args.host, args.port), Handler).serve_forever()
