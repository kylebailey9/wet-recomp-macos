import Foundation
import SwiftUI
import Sodium

enum SetupError: Error, LocalizedError {
    case msg(String)
    var errorDescription: String? {
        if case .msg(let s) = self { return s }
        return "Unknown error"
    }
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var token = ""
    @Published var tokenStatus = ""
    @Published var owner = "kylebailey9"
    @Published var repo = "wet-recomp-macos"
    @Published var repoStatus = ""
    @Published var branch = "main"
    @Published var isoStatus = ""
    @Published var log = ""
    @Published var passphrase: String?
    @Published var actionsURL: URL?
    @Published var running = false
    @Published var canGo = false

    private var xexData: Data?

    private func appendLog(_ s: String) { log += s + "\n" }

    // MARK: - GitHub API

    private func gh(_ path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, Int) {
        guard !token.isEmpty else { throw SetupError.msg("Connect your GitHub token first (step 1).") }
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func connectToken() async {
        do {
            let (data, code) = try await gh("/user")
            guard code == 200 else { throw SetupError.msg("Token rejected (HTTP \(code)).") }
            let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let login = j?["login"] as? String ?? "?"
            tokenStatus = "Connected as \(login)"
            appendLog("Token OK (\(login))")
        } catch {
            tokenStatus = "Token rejected."
            appendLog("Token failed: \(error.localizedDescription)")
        }
    }

    func checkRepo() async {
        do {
            let (data, code) = try await gh("/repos/\(owner)/\(repo)")
            guard code == 200 else { throw SetupError.msg("Repo not found or no access (HTTP \(code)).") }
            let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            branch = (j?["default_branch"] as? String) ?? "main"
            repoStatus = "\(owner)/\(repo) ✓ (branch: \(branch))"
            appendLog("Repo OK: \(owner)/\(repo)")
        } catch {
            repoStatus = "Repo not found or no access."
            appendLog("Repo check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - ISO / XEX

    func handleISO(_ url: URL) async {
        isoStatus = "Reading ISO…"
        appendLog("Parsing ISO…")
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try XisoReader.extractDefaultXex(from: url)
            acceptXex(data, label: "default.xex (extracted from ISO)")
        } catch {
            isoStatus = "Could not find default.xex in that file. Is it an Xbox 360 ISO?"
            appendLog("ISO parse failed: \(error.localizedDescription)")
        }
    }

    func handleXEXFile(_ url: URL) async {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            acceptXex(data, label: url.lastPathComponent)
        } catch {
            isoStatus = "Could not read that file."
            appendLog("File read failed: \(error.localizedDescription)")
        }
    }

    private func acceptXex(_ data: Data, label: String) {
        guard data.count > 20_000_000 else {
            isoStatus = "\(label) is only \(data.count / 1_000_000) MB — WET's default.xex is about 22.4 MB. Wrong file?"
            appendLog("XEX size check failed: \(data.count) bytes")
            return
        }
        xexData = data
        isoStatus = "✓ \(label) — \(data.count / 1_000_000) MB, looks right."
        canGo = true
        appendLog("XEX ready: \(data.count) bytes")
    }

    // MARK: - Do everything

    func doEverything() async {
        running = true
        defer { running = false }
        do {
            guard let xex = xexData else { throw SetupError.msg("Select your ISO first (step 3).") }

            appendLog("Step 1/6: encrypting default.xex…")
            let pp = WetCrypto.randomPassphrase()
            passphrase = pp
            let enc = try WetCrypto.encryptXex(xex, passphrase: pp)
            appendLog("Encrypted: \(enc.count / 1_000_000) MB")

            appendLog("Step 2/6: creating workflow file…")
            try await putFile(path: ".github/workflows/build-macos.yml",
                              data: Data(WORKFLOW_YML.utf8),
                              message: "Add GitHub Actions cloud build for macOS (Apple Silicon)")
            appendLog("Workflow file OK")

            appendLog("Step 3/6: updating .gitignore…")
            var gi = (try? await getFile(path: ".gitignore")) ?? ""
            if !gi.contains("!game/default.xex.enc") { gi += "\n!game/default.xex.enc\n" }
            try await putFile(path: ".gitignore",
                              data: Data(gi.utf8),
                              message: "Allow encrypted default.xex for cloud builds")
            appendLog(".gitignore OK")

            appendLog("Step 4/6: uploading game/default.xex.enc (\(enc.count / 1_000_000) MB, this takes a bit)…")
            try await putFile(path: "game/default.xex.enc",
                              data: enc,
                              message: "Add encrypted default.xex for cloud build")
            appendLog("Upload OK")

            appendLog("Step 5/6: saving WET_XEX_PASSPHRASE secret…")
            try await putSecret(name: "WET_XEX_PASSPHRASE", value: pp)
            appendLog("Secret saved")

            appendLog("Step 6/6: starting the cloud build…")
            var dispatched = false
            for _ in 0..<4 {
                if dispatched { break }
                do {
                    try await dispatchWorkflow()
                    dispatched = true
                } catch {
                    appendLog("Dispatch not ready yet, retrying…")
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
            guard dispatched else { throw SetupError.msg("Could not dispatch. Run it manually from the Actions tab.") }
            appendLog("Build dispatched!")
            actionsURL = URL(string: "https://github.com/\(owner)/\(repo)/actions")
            appendLog("Watch it here: \(actionsURL!.absoluteString)")
        } catch {
            appendLog("FAILED: \(error.localizedDescription)")
        }
    }

    private func getFile(path: String) async throws -> String {
        let (data, code) = try await gh("/repos/\(owner)/\(repo)/contents/\(path)?ref=\(branch)")
        guard code == 200 else { throw SetupError.msg("GET \(path) → HTTP \(code)") }
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let b64 = j?["content"] as? String else { throw SetupError.msg("Bad response for \(path)") }
        let clean = b64.replacingOccurrences(of: "\n", with: "")
        guard let d = Data(base64Encoded: clean),
              let s = String(data: d, encoding: .utf8) else {
            throw SetupError.msg("Could not decode \(path)")
        }
        return s
    }

    private func putFile(path: String, data: Data, message: String) async throws {
        var sha: String?
        let (gdata, gcode) = try await gh("/repos/\(owner)/\(repo)/contents/\(path)?ref=\(branch)")
        if gcode == 200 {
            let j = try JSONSerialization.jsonObject(with: gdata) as? [String: Any]
            sha = j?["sha"] as? String
        }
        var body: [String: Any] = [
            "message": message,
            "content": data.base64EncodedString(),
            "branch": branch
        ]
        if let sha = sha { body["sha"] = sha }
        let payload = try JSONSerialization.data(withJSONObject: body)
        let (_, pcode) = try await gh("/repos/\(owner)/\(repo)/contents/\(path)", method: "PUT", body: payload)
        guard (200...299).contains(pcode) else { throw SetupError.msg("PUT \(path) → HTTP \(pcode)") }
    }

    private func putSecret(name: String, value: String) async throws {
        let (kdata, kcode) = try await gh("/repos/\(owner)/\(repo)/actions/secrets/public-key")
        guard kcode == 200 else { throw SetupError.msg("Could not get repo public key (HTTP \(kcode))") }
        let kj = try JSONSerialization.jsonObject(with: kdata) as? [String: Any]
        guard let keyId = kj?["key_id"] as? String,
              let keyB64 = kj?["key"] as? String,
              let keyData = Data(base64Encoded: keyB64) else {
            throw SetupError.msg("Bad public key response")
        }
        let sodium = Sodium()
        guard let sealed = sodium.box.seal(message: Array(value.utf8), recipientPublicKey: Array(keyData)) else {
            throw SetupError.msg("Sealed-box encryption failed")
        }
        let payload = try JSONSerialization.data(withJSONObject: [
            "encrypted_value": Data(sealed).base64EncodedString(),
            "key_id": keyId
        ])
        let (_, scode) = try await gh("/repos/\(owner)/\(repo)/actions/secrets/\(name)", method: "PUT", body: payload)
        guard (200...299).contains(scode) else { throw SetupError.msg("PUT secret → HTTP \(scode)") }
    }

    private func dispatchWorkflow() async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["ref": branch])
        let (_, dcode) = try await gh("/repos/\(owner)/\(repo)/actions/workflows/build-macos.yml/dispatches",
                                      method: "POST", body: payload)
        guard dcode == 204 else { throw SetupError.msg("Dispatch → HTTP \(dcode)") }
    }
}

// MARK: - Embedded workflow (created in the repo by the app)

private let WORKFLOW_YML = """
# GitHub Actions: build the native Apple Silicon WET binary in the cloud.
#
# Trigger it manually: Actions tab -> "Build macOS (Apple Silicon)" -> Run workflow.
# macOS runners bill at 10x minutes, so this only runs when you ask it to.
#
# One-time setup (on your Mac, see CI.md):
#   1. Commit your encrypted game/default.xex.enc to this repo.
#   2. Add its passphrase as the WET_XEX_PASSPHRASE Actions secret.
# Afterwards, download the `wet-macos-arm64` artifact and drop the files
# next to your own game/ folder to play.

name: Build macOS (Apple Silicon)

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-15 # Apple Silicon (M1) runner, Xcode 16
    timeout-minutes: 240
    steps:
      - name: Check out this repo
        uses: actions/checkout@v4
        with:
          path: add-on

      - name: Clone upstream wet-recomp
        run: git clone --depth 1 https://github.com/Supermedo/wet-recomp.git wet-recomp

      - name: Overlay add-on files
        run: |
          set -euo pipefail
          cd wet-recomp
          cp ../add-on/*.sh ../add-on/launch-native.command .
          cp ../add-on/wet_manifest.toml .
          cp ../add-on/patches/*.patch patches/
          chmod +x *.sh launch-native.command

      - name: Install build dependencies
        run: |
          set -euo pipefail
          xcodebuild -version
          brew install cmake ninja molten-vk vulkan-headers
          # extract-xiso is not in Homebrew core; build it from source.
          git clone --depth 1 https://github.com/XboxDev/extract-xiso.git /tmp/extract-xiso
          cmake -S /tmp/extract-xiso -B /tmp/extract-xiso/build -DCMAKE_BUILD_TYPE=Release
          cmake --build /tmp/extract-xiso/build -j3
          sudo cmake --install /tmp/extract-xiso/build

      - name: Decrypt default.xex
        env:
          WET_XEX_PASSPHRASE: ${{ secrets.WET_XEX_PASSPHRASE }}
        run: |
          set -euo pipefail
          test -n "${WET_XEX_PASSPHRASE:-}" || { echo "::error::Missing WET_XEX_PASSPHRASE secret (see CI.md)."; exit 1; }
          test -f add-on/game/default.xex.enc || { echo "::error::Missing add-on/game/default.xex.enc (see CI.md)."; exit 1; }
          mkdir -p wet-recomp/game
          openssl enc -d -aes-256-cbc -pbkdf2 \\
            -in add-on/game/default.xex.enc \\
            -out wet-recomp/game/default.xex \\
            -pass env:WET_XEX_PASSPHRASE
          size=$(stat -f%z wet-recomp/game/default.xex)
          echo "default.xex: $size bytes"
          # WET's default.xex is about 22.4 MB; anything far smaller means
          # the wrong file was encrypted or the passphrase is wrong.
          test "$size" -gt 20000000 || { echo "::error::Decrypted file too small — wrong file or bad passphrase."; exit 1; }

      - name: Apply patches and clone ReXGlue SDK
        run: |
          set -euo pipefail
          cd wet-recomp
          git apply patches/wet-recomp-macos.patch
          git clone --branch v0.10.0 --depth 1 https://github.com/rexglue/rexglue-sdk.git thirdparty/rexglue-sdk
          git -C thirdparty/rexglue-sdk apply ../../patches/rexglue-sdk-macos.patch

      - name: Setup and codegen
        run: |
          set -euo pipefail
          cd wet-recomp
          ./setup-macos.sh
          cp ../add-on/wet_manifest.toml .
          cmake --build out/build/mac-arm64-release --target wet_codegen

      - name: Build
        run: |
          set -euo pipefail
          cd wet-recomp
          ./build-macos.sh

      - name: Upload binary
        uses: actions/upload-artifact@v4
        with:
          name: wet-macos-arm64
          path: |
            wet-recomp/wet
            wet-recomp/*.dylib
            wet-recomp/MoltenVK_icd.json
          if-no-files-found: error
"""
