import AppKit
import WebKit
import Foundation
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private enum Constants {
        static let appName = "Daily Help"
        static let windowTitle = "Daily Help"
        static let windowSubtitle = "Mac 文件命令"
        static let autosaveName = "DailyHelpMainWindow"
        static let defaultSize = NSSize(width: 1240, height: 820)
        static let minSize = NSSize(width: 1000, height: 640)
        static let pageBaseURL = URL(string: "https://dailyhelp.local/")!
        static let smokePasteboard = NSPasteboard.Name("DailyHelpSmokeTest")
    }

    let isSmokeTest = CommandLine.arguments.contains("--smoke-test")
    private var window: NSWindow?
    private var webView: WKWebView?
    private var smokeTimeout: DispatchWorkItem?
    private var smokeFinished = false
    private var smokeChecksStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        createWindowAndWebView()
        loadPage()

        if isSmokeTest {
            let timeout = DispatchWorkItem { [weak self] in
                self?.finishSmokeTest(success: false, detail: "timeout")
            }
            smokeTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        } else {
            window?.makeKeyAndOrderFront(nil)
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.makeKeyAndOrderFront(nil) }
        return true
    }

    private func createWindowAndWebView() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "nativeCopy")
        controller.add(self, name: "themeChanged")
        controller.addUserScript(WKUserScript(
            source: Self.bridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Self.bridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Self.appStyleScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.allowsMagnification = false
        web.underPageBackgroundColor = .windowBackgroundColor

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = Constants.windowTitle
        win.subtitle = Constants.windowSubtitle
        win.minSize = Constants.minSize
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.backgroundColor = .windowBackgroundColor
        win.isOpaque = true
        win.contentView = web

        let savedFrameKey = "NSWindow Frame \(Constants.autosaveName)"
        let hasSavedFrame = UserDefaults.standard.string(forKey: savedFrameKey) != nil
        win.setFrameAutosaveName(Constants.autosaveName)
        if !hasSavedFrame { win.center() }

        self.window = win
        self.webView = web
    }

    private func loadPage() {
        guard let htmlURL = bundledHTMLURL(),
              let html = try? String(contentsOf: htmlURL, encoding: .utf8) else {
            handleLoadFailure(message: "找不到或无法读取 web/index.html")
            return
        }
        webView?.loadHTMLString(html, baseURL: Constants.pageBaseURL)
    }

    private func bundledHTMLURL() -> URL? {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            return url
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidate = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/web/index.html")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isSmokeTest else { return }
        runSmokeChecks()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(message: "页面加载失败：\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(message: "页面加载失败：\(error.localizedDescription)")
    }

    private func handleLoadFailure(message: String) {
        if isSmokeTest {
            finishSmokeTest(success: false, detail: message)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Daily Help 无法启动"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }

    private func runSmokeChecks() {
        guard !smokeChecksStarted else { return }
        smokeChecksStarted = true

        let testPasteboard = NSPasteboard(name: Constants.smokePasteboard)
        testPasteboard.clearContents()

        let script = """
        (() => {
          const rows = document.querySelectorAll('.cmd-row').length;
          let storage = 'fail';
          try {
            localStorage.setItem('__dh_smoke__', 'ok');
            storage = localStorage.getItem('__dh_smoke__') === 'ok' ? 'ok' : 'fail';
            localStorage.removeItem('__dh_smoke__');
          } catch (error) {
            storage = 'fail';
          }
          if (typeof window.copyCommand === 'function') {
            window.copyCommand('png-to-jpg');
          }
          return JSON.stringify({ rows, storage });
        })()
        """

        webView?.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            if let error = error {
                self.finishSmokeTest(success: false, detail: "js error: \(error.localizedDescription)")
                return
            }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data),
                  let object = parsed as? [String: Any] else {
                self.finishSmokeTest(success: false, detail: "bad js result: \(String(describing: result))")
                return
            }
            let rows = object["rows"] as? Int ?? -1
            let storage = object["storage"] as? String ?? "fail"

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let pasted = testPasteboard.string(forType: .string) ?? ""
                let clipboardOK = pasted.contains("sips -s format jpeg")
                let success = rows == 26 && storage == "ok" && clipboardOK
                let detail = "rows=\(rows) storage=\(storage) clipboard=\(clipboardOK ? "ok" : "fail")"
                self.finishSmokeTest(success: success, detail: detail)
            }
        }
    }

    private func finishSmokeTest(success: Bool, detail: String) {
        guard !smokeFinished else { return }
        smokeFinished = true
        smokeTimeout?.cancel()
        smokeTimeout = nil

        if success {
            print("SMOKE_OK rows=26 storage=ok clipboard=ok")
            exit(0)
        } else {
            print("SMOKE_FAIL \(detail)")
            exit(1)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "nativeCopy":
            guard let text = message.body as? String else { return }
            let pasteboard = isSmokeTest
                ? NSPasteboard(name: Constants.smokePasteboard)
                : NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

        case "themeChanged":
            guard let theme = message.body as? String else { return }
            window?.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)

        default:
            break
        }
    }

    @objc private func reloadPage(_ sender: Any?) {
        loadPage()
    }

    @objc private func zoomIn(_ sender: Any?) {
        guard let webView else { return }
        webView.pageZoom = min(webView.pageZoom + 0.1, 2.0)
    }

    @objc private func zoomOut(_ sender: Any?) {
        guard let webView else { return }
        webView.pageZoom = max(webView.pageZoom - 0.1, 0.5)
    }

    @objc private func resetZoom(_ sender: Any?) {
        webView?.pageZoom = 1.0
    }

    @objc private func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(nil)
    }

    @objc private func minimizeWindow(_ sender: Any?) {
        window?.performMiniaturize(nil)
    }

    @objc private func zoomWindow(_ sender: Any?) {
        window?.performZoom(nil)
    }

    @objc private func showHelp(_ sender: Any?) {
        webView?.evaluateJavaScript("document.querySelector('#help-button')?.click()", completionHandler: nil)
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: Constants.appName)
        appMenuItem.submenu = appMenu

        let about = appMenu.addItem(
            withTitle: "关于 Daily Help",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        appMenu.addItem(.separator())

        let hide = appMenu.addItem(
            withTitle: "隐藏 Daily Help",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hide.target = NSApp

        let hideOthers = appMenu.addItem(
            withTitle: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp

        let showAll = appMenu.addItem(
            withTitle: "显示全部",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAll.target = NSApp
        appMenu.addItem(.separator())

        let quit = appMenu.addItem(
            withTitle: "退出 Daily Help",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "显示")
        viewMenuItem.submenu = viewMenu

        let reload = viewMenu.addItem(
            withTitle: "重新载入",
            action: #selector(reloadPage(_:)),
            keyEquivalent: "r"
        )
        reload.target = self
        viewMenu.addItem(.separator())

        let zoomInItem = viewMenu.addItem(
            withTitle: "放大",
            action: #selector(zoomIn(_:)),
            keyEquivalent: "="
        )
        zoomInItem.target = self

        let zoomOutItem = viewMenu.addItem(
            withTitle: "缩小",
            action: #selector(zoomOut(_:)),
            keyEquivalent: "-"
        )
        zoomOutItem.target = self

        let actualSize = viewMenu.addItem(
            withTitle: "实际大小",
            action: #selector(resetZoom(_:)),
            keyEquivalent: "0"
        )
        actualSize.target = self
        viewMenu.addItem(.separator())

        let fullScreen = viewMenu.addItem(
            withTitle: "进入全屏幕",
            action: #selector(toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        fullScreen.target = self

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu

        let minimize = windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(minimizeWindow(_:)),
            keyEquivalent: "m"
        )
        minimize.target = self

        let zoomWindowItem = windowMenu.addItem(
            withTitle: "缩放",
            action: #selector(zoomWindow(_:)),
            keyEquivalent: ""
        )
        zoomWindowItem.target = self
        windowMenu.addItem(.separator())

        let front = windowMenu.addItem(
            withTitle: "前置全部窗口",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        front.target = NSApp
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "帮助")
        helpMenuItem.submenu = helpMenu

        let help = helpMenu.addItem(
            withTitle: "使用说明",
            action: #selector(showHelp(_:)),
            keyEquivalent: ""
        )
        help.target = self
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    private static let bridgeScript = #"""
    (() => {
      if (!window.__dailyHelpClipboardPatched) {
        const copyHandler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeCopy;
        if (copyHandler) {
          const sendCopy = (text) => {
            try { copyHandler.postMessage(String(text)); return true; } catch (error) { return false; }
          };
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText = function(text) {
              sendCopy(text);
              return Promise.resolve();
            };
          }
          const originalExecCommand = document.execCommand ? document.execCommand.bind(document) : null;
          document.execCommand = function(command, ...args) {
            if (command === 'copy') {
              const active = document.activeElement;
              const text = active && typeof active.value === 'string'
                ? active.value
                : (window.getSelection ? window.getSelection().toString() : '');
              if (sendCopy(text)) return true;
            }
            return originalExecCommand ? originalExecCommand(command, ...args) : false;
          };
          window.__dailyHelpClipboardPatched = true;
        }
      }

      if (!window.__dailyHelpThemePatched) {
        const themeHandler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.themeChanged;
        if (themeHandler) {
          const reportTheme = () => {
            themeHandler.postMessage(document.documentElement.dataset.theme || 'light');
          };
          new MutationObserver(reportTheme).observe(document.documentElement, {
            attributes: true,
            attributeFilter: ['data-theme']
          });
          document.addEventListener('DOMContentLoaded', reportTheme);
          reportTheme();
          window.__dailyHelpThemePatched = true;
        }
      }
    })();
    """#

    private static let appCSS = #"""
    html, body {
      height: 100% !important;
    }
    body {
      padding: 0 !important;
      display: block !important;
      background: var(--window) !important;
    }
    .app {
      width: 100% !important;
      height: 100vh !important;
      height: 100dvh !important;
      border: 0 !important;
      border-radius: 0 !important;
      box-shadow: none !important;
    }
    .titlebar .traffic,
    .titlebar .app-id {
      display: none !important;
    }
    .titlebar {
      padding-left: 12px !important;
      padding-right: 12px !important;
    }
    .titlebar .search-wrap {
      margin-left: 0 !important;
      flex: 1 1 auto !important;
      max-width: none !important;
    }
    """#

    private static let appStyleScript: String = {
        let data = try! JSONEncoder().encode(appCSS)
        let json = String(data: data, encoding: .utf8)!
        return """
        (() => {
          const old = document.getElementById('dailyhelp-app-style');
          if (old) old.remove();
          const style = document.createElement('style');
          style.id = 'dailyhelp-app-style';
          style.textContent = \(json);
          document.head.appendChild(style);
        })();
        """
    }()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(delegate.isSmokeTest ? .accessory : .regular)
app.run()
