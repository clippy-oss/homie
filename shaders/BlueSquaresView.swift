import SwiftUI
import WebKit

struct BlueSquaresView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        
        if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html") {
            let htmlUrl = URL(fileURLWithPath: htmlPath)
            let request = URLRequest(url: htmlUrl)
            webView.load(request)
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }
}

// Usage in SwiftUI:
// BlueSquaresView()
//     .ignoresSafeArea()