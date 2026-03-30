import SwiftUI

struct ContentView: View {
    var body: some View {
        ChatView()
    }
}

// MARK: - Marmalade Theme Colors

extension Color {
    static let marmaladeBg    = Color(red: 26/255,  green: 15/255,  blue: 0/255)
    static let marmaladeBg2   = Color(red: 45/255,  green: 24/255,  blue: 16/255)
    static let marmaladeBg3   = Color(red: 13/255,  green: 8/255,   blue: 5/255)
    static let marmaladeAmber = Color(red: 245/255, green: 166/255, blue: 35/255)
    static let marmaladeTan   = Color(red: 196/255, green: 149/255, blue: 106/255)
    static let marmaladeCream = Color(red: 245/255, green: 230/255, blue: 211/255)
    static let marmaladeMuted = Color(red: 160/255, green: 134/255, blue: 112/255)
    static let marmaladeMint  = Color(red: 149/255, green: 213/255, blue: 178/255)
}
